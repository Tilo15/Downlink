using Downlink.Util;

namespace Downlink {

    public class ResourceIdentifier {

        private uint8[] auth_table_hash;
        public uint64 size { get; private set; }

        public string to_string() {
            return @"$(base64_encode(auth_table_hash))$size";
        }

        public ResourceIdentifier.from_string(string str) {
            var parts = str.split("==");
            auth_table_hash = base64_decode(parts[0] + "==");
            size = uint64.parse(parts[1]);
        }

    }

}