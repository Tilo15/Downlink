using Sodium.Asymmetric;
using Downlink.Util;

namespace Downlink {

    public class PublishingKey {

        public uint8[] public_key { get; set; }
        public uint8[] secret_key { get; set; }

        public PublishingKey() {
            public_key = new uint8[Signing.PUBLIC_KEY_BYTES];
            secret_key = new uint8[Signing.SECRET_KEY_BYTES];
            Signing.generate_keypair (public_key, secret_key);
        }

        public PublishingKey.from_string(string str) {
            var parts = str.split(".");
            public_key = base64_decode (parts[0]);
            secret_key = base64_decode (parts[1]);
        }

        public string to_string() {
            return @"$(base64_encode(public_key)).$(base64_encode(secret_key))";
        }

        public uint8[] sign(uint8[] data) {
            return Signing.sign(data, secret_key);
        }

        public PublisherKey get_publisher_key() {
            return new PublisherKey(public_key);
        }

    }

}