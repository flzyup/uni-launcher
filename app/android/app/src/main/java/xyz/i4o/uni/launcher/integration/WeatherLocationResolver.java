package xyz.i4o.uni.launcher.integration;

import java.io.IOException;
import java.util.*;

/** Location matching is independent of Android/network, so wrong-city forecast
 * regressions can be tested using the service's actual response shapes. */
public final class WeatherLocationResolver {
    public interface Lookup { List<Place> search(String query) throws Exception; }
    public interface Romanizer { String romanize(String value); }
    public static final class NotFound extends IOException {
        public NotFound(){super("No matching district or city");}
    }
    public static final class Place {
        public final String name,country,province,city,district,feature;
        public final double latitude,longitude;
        public final long population;
        public Place(String name,String country,String province,String city,String district,
                String feature,double latitude,double longitude,long population){
            this.name=name;this.country=country;this.province=province;this.city=city;
            this.district=district;this.feature=feature;this.latitude=latitude;
            this.longitude=longitude;this.population=population;
        }
    }
    public static final class Location {
        public final Place place;
        public final String label;
        public final boolean cityFallback;
        Location(Place place,String label,boolean fallback){this.place=place;this.label=label;this.cityFallback=fallback;}
    }
    public static String normalized(String value){
        if(value==null)return "";
        return value.trim().replaceAll("(?:特别行政区|壮族自治区|回族自治区|维吾尔自治区|自治区|自治州|省|市|(?<![社小园])区|县)$","")
            .replaceAll("[\\s'-]","").toLowerCase(Locale.ROOT);
    }
    private static boolean same(String a,String b,Romanizer romanizer){
        if(normalized(a).isEmpty()||normalized(b).isEmpty())return false;
        if(normalized(a).equals(normalized(b)))return true;
        // Homophones are not administrative aliases (闵行 -> 民兴 is wrong).
        // Transliteration may match a Latin result name, never two different
        // Chinese names inside the same province/city.
        if(a.matches(".*[\\u3400-\\u9fff].*")&&b.matches(".*[\\u3400-\\u9fff].*"))return false;
        String left=romanizer.romanize(normalized(a)),right=romanizer.romanize(normalized(b));
        return left!=null&&right!=null&&!left.isEmpty()&&normalized(left).equals(normalized(right));
    }
    private static Set<String> queries(String name,Romanizer romanizer){
        Set<String> result=new LinkedHashSet<>();
        if(name==null||name.trim().isEmpty())return result;
        // Administrative suffixes are not indexed consistently. Never search
        // a full street address or concatenate province/city/district blindly.
        result.add(name.trim());result.add(normalized(name));
        String latin=romanizer.romanize(normalized(name));
        if(latin!=null&&!latin.isEmpty())result.add(latin.replaceAll("\\s+", ""));
        return result;
    }
    private static Place choose(List<Place> places,String name,String region,Romanizer romanizer){
        Place best=null;long score=Long.MIN_VALUE;
        for(Place p:places){
            if(!"CN".equalsIgnoreCase(p.country)||!Double.isFinite(p.latitude)||!Double.isFinite(p.longitude)
                    ||Math.abs(p.latitude)>90||Math.abs(p.longitude)>180||!same(p.name,name,romanizer))continue;
            if(!p.feature.startsWith("PPLA")&&!p.feature.startsWith("ADM")&&!p.feature.equals("PPLC"))continue;
            if(!region.isEmpty()&&!same(p.province,region,romanizer)&&!same(p.city,region,romanizer)
                    &&!same(p.district,region,romanizer)
                    &&!(!p.province.isEmpty()&&!p.city.isEmpty()
                        &&region.contains(p.province)&&region.contains(p.city)))continue;
            long next=(p.feature.startsWith("PPLA")?1_000_000_000L:0)+Math.max(0,Math.min(p.population,999_999_999));
            if(next>score){best=p;score=next;}
        }return best;
    }
    public static Location resolve(String district,String region,Lookup lookup,Romanizer romanizer)throws Exception{
        district=district==null?"":district.trim();region=region==null?"":region.trim();
        for(String query:queries(district,romanizer)){
            Place found=choose(lookup.search(query),district,region,romanizer);
            if(found!=null)return new Location(found,district,false);
        }
        if(!normalized(region).equals(normalized(district))){
            String city=region.replaceFirst("^.*(?:省|自治区|特别行政区)","");
            for(String query:queries(city,romanizer)){
                Place found=choose(lookup.search(query),city,region,romanizer);
                if(found!=null)return new Location(found,city,true);
            }
        }
        throw new NotFound();
    }
    private WeatherLocationResolver(){}
}
