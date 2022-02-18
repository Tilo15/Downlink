
namespace Downlink {

    public class File {

        public string name { get; set; }
        public ResourceIdentifier resource { get; set; }
        
        public File(string name, ResourceIdentifier identifier) {
            this.name = name;
            resource = identifier;
        }

        public File.from_json(Json.Object obj) {
            name = obj.get_string_member ("name");
            resource = new ResourceIdentifier.from_string(obj.get_string_member ("resource"));
        }

        public void to_json(Json.Builder builder) {
            builder.begin_object();

            builder.set_member_name("name");
            builder.add_string_value(name);

            builder.set_member_name("resource");
            builder.add_string_value(resource.to_string());

            builder.end_object();
        }

    }

}