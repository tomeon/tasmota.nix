# Example configuration shared by the tests.  Secret paths are relative,
# so the integration test can provide the files in its working directory.
{lib, ...}: {
  decode-config = {
    defaults = {
      tags = ["home"];
      settings.mqtt_host = lib.mkDefault "broker.lan";
    };

    devices.kitchen = {
      source = "http://kitchen.lan";
      passwordFile = "web";
      tags = ["lights"];
      settings = {
        hostname = "kitchen";
        sta_pwd = [{_secret = "wifi";}];
      };
    };

    devices.plug = {
      extraArgs = ["--json-indent" "2"];
      settings = {
        hostname = "plug";
        mqtt_host = "other.lan";
      };
    };
  };
}
