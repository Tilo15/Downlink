using LibPeer.Util;
using Downlink.Util;

namespace Downlink {

    public class Metadata {

        private uint8[] raw;
        public PublisherKey publisher { get; private set; }
        public DateTime expiry { get; set; }
        public DateTime published { get; private set; }
        public Folder root { get; set; }
        
        public Metadata(DateTime expiry) {
            root = new Folder("");
            this.expiry = expiry;
        }

        public Metadata.from_bytes(uint8[] data, PublisherKey key) throws Error {
            raw = data.copy();
            publisher = key;
            var json_data = bytes_to_string(key.verify(raw));

            var parser = new Json.Parser();
            parser.load_from_data(json_data);
            var obj = parser.get_root().get_object();

            expiry = new DateTime.from_iso8601(obj.get_string_member("expiry"), null);
            published = new DateTime.from_iso8601(obj.get_string_member("published"), null);
            root = new Folder.from_json(obj.get_object_member("root"));
        }

        public void to_json(Json.Builder builder) {
            builder.begin_object();

            builder.set_member_name("published");
            builder.add_string_value(published.format_iso8601());

            builder.set_member_name("expiry");
            builder.add_string_value(expiry.format_iso8601());

            builder.set_member_name("root");
            root.to_json(builder);

            builder.end_object();
        }

        public void publish(PublishingKey key) {
            publisher = key.get_publisher_key();
            var builder = new Json.Builder();
            published = new DateTime.now_utc();
            to_json(builder);
            var generator = new Json.Generator ();
            var root_node = builder.get_root ();
            generator.set_root (root_node);

            var json = generator.to_data(null);
            raw = key.sign(string_to_bytes(json));
        }

        public uint8[] to_bytes() {
            return raw.copy();
        }

    }

}