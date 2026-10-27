import java.util.*;
import java.net.SocketTimeoutException;
import xyz.i4o.uni.launcher.integration.WeatherLocationResolver;
import xyz.i4o.uni.launcher.integration.WeatherLocationResolver.*;

public class WeatherLocationResolverTest {
    static int count;
    static void check(boolean value,String message){count++;if(!value)throw new AssertionError(message);}
    static Place place(String name,String province,String city,double lat,double lon){
        return new Place(name,"CN",province,city,"","PPLA",lat,lon,100);
    }
    public static void main(String[] args)throws Exception{
        Romanizer identity=s->s;
        Place shanghai=place("上海","上海市","上海市",31.22222,121.45806);
        Place falseShanghai=place("上海市场社区","河南","洛阳市",34.66295,112.38329);
        List<String> queries=new ArrayList<>();
        Location city=WeatherLocationResolver.resolve("闵行区","上海市",q->{
            queries.add(q);
            if(q.equals("上海市"))return Arrays.asList(falseShanghai);
            return q.equals("上海")?Arrays.asList(shanghai):Collections.emptyList();
        },identity);
        check(city.place==shanghai,"district lookup falls back to the actual municipality");
        check(city.cityFallback,"city fallback is explicit");
        check(city.label.equals("上海市"),"forecast label does not masquerade as district");
        check(queries.equals(Arrays.asList("闵行区","闵行","上海市","上海")),"suffix variants searched; no blind joined address");
        Place wrong=place("鼓楼区","福建省","福州市",26.08,119.3);
        Place right=place("鼓楼区","江苏省","南京市",32.07,118.77);
        Location district=WeatherLocationResolver.resolve("鼓楼区","南京市",q->Arrays.asList(wrong,right),identity);
        check(district.place==right,"same district name uses parent city");
        check(!district.cityFallback,"exact district remains district forecast");
        check(WeatherLocationResolver.resolve("鼓楼区","江苏省南京市",q->Arrays.asList(wrong,right),identity).place==right,"combined province and city constraint");
        Place xihu=place("Xihu","浙江省","杭州市",30.25,120.1);
        Romanizer latin=s->s.equals("西湖")?"Xihu":s;
        check(WeatherLocationResolver.resolve("西湖区","杭州市",q->q.equals("Xihu")?Arrays.asList(xihu):Collections.emptyList(),latin).place==xihu,"romanization fallback retains city constraint");
        Place invalid=new Place("上海","CN","上海市","上海市","","PPLA",Double.NaN,121,100);
        Place foreign=new Place("上海","US","上海市","上海市","","PPLA",31,121,100);
        try{WeatherLocationResolver.resolve("上海","上海市",q->Arrays.asList(invalid,foreign,falseShanghai),identity);throw new AssertionError("invalid locations accepted");}
        catch(NotFound expected){check(true,"missing, foreign and malformed coordinates rejected");}
        try{WeatherLocationResolver.resolve("闵行区","上海市",q->{throw new SocketTimeoutException();},identity);throw new AssertionError("network errors swallowed");}
        catch(SocketTimeoutException expected){check(true,"network failure distinguished from location not found");}
        check(WeatherLocationResolver.normalized("上海市").equals("上海"),"municipal suffix normalized");
        check(WeatherLocationResolver.normalized("广西壮族自治区").equals("广西"),"autonomous region normalized");
        check(WeatherLocationResolver.normalized("上海市场社区").equals("上海市场社区"),"do not truncate unrelated place names");
        Place minxing=new Place("民兴","CN","上海市","上海市","","PPL",31.3642,121.83257,100);
        Romanizer homophone=s->s.equals("闵行")||s.equals("民兴")?"minxing":s;
        Location safe=WeatherLocationResolver.resolve("闵行区","上海市",q->q.equals("上海")?Arrays.asList(shanghai):Arrays.asList(minxing),homophone);
        check(safe.place==shanghai&&safe.cityFallback,"same-city homophonic village cannot impersonate district");
        System.out.println("PASS "+count+" forecast location checks; no network or device access");
    }
}
