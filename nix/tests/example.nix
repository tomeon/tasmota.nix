# Example configuration shared by the tests.  The integration test points
# the secret paths at files of its own.
{lib, ...}: {
  decode-config = {
    defaults = {
      tags = ["home"];
      settings.mqtt_host = lib.mkDefault "broker.lan";
    };

    devices.kitchen = {
      source = "http://kitchen.lan";
      passwordFile = "/run/secrets/tasmota-web";
      tags = ["lights"];
      settings = {
        hostname = "kitchen";
        sta_pwd = [{_secret = "/run/secrets/wifi";}];
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
