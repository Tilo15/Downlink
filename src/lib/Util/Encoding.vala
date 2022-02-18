
namespace Downlink.Util {

    public static string base64_encode(uint8[] data) {
        return Base64.encode(data).replace("/", "_");
    }

    public static uint8[] base64_decode(string str) {
        return Base64.decode(str.replace("_", "/"));
    }

}