using Sodium.Asymmetric;
using Downlink.Util;

namespace Downlink {

    public class PublisherKey {

        public uint8[] public_key { get; set; }

        public string identifier { 
            owned get {
                return base64_encode (public_key);
            }
        }

        public PublisherKey(uint8[] key_bytes) {
            public_key = key_bytes;
        }

        public PublisherKey.from_string(string id) {
            public_key = base64_decode (id);
        }

        public uint8[] verify(uint8[] data) {
            return Signing.verify(data, public_key);
        }

        public uint hash() {
            return new Bytes(public_key).hash();
        }

        public int compare(PublisherKey other) {
            return new Bytes(public_key).compare(new Bytes(other.public_key));
        }

    }

}