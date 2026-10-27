package xyz.i4o.uni.launcher.integration;

import org.json.JSONObject;

/** No UI component calls an OEM method directly. Commands require a verified adapter. */
public interface VehicleAdapter {
    JSONObject snapshot();
    boolean command(String action, String zone, String mode);
    void close();
}
