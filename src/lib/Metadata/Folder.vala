using LibPeer.Util;

namespace Downlink {

    public class Folder {

        public string name { get; set; }
        public ConcurrentHashMap<string, Folder> folders { get; set; }
        public ConcurrentHashMap<string, File> files { get; set; }
        
        public Folder(string name) {
            this.name = name;
            folders = new ConcurrentHashMap<string, Folder>();
            files = new ConcurrentHashMap<string, File>();
        }

        public Folder.from_json(Json.Object obj) {
            name = obj.get_string_member ("name");
            folders = new ConcurrentHashMap<string, Folder>();
            files = new ConcurrentHashMap<string, File>();

            var folds = obj.get_array_member("subfolders");
            for(var i = 0; i < folds.get_length(); i++) {
                var folder = new Folder.from_json (folds.get_object_element(i));
                folders.set(folder.name, folder);
            }

            var fils = obj.get_array_member("files");
            for(var i = 0; i < fils.get_length(); i++) {
                var file = new File.from_json (fils.get_object_element(i));
                files.set(file.name, file);
            }
        }

        public void to_json(Json.Builder builder) {
            builder.begin_object();

            builder.set_member_name("name");
            builder.add_string_value(name);

            builder.set_member_name("subfolders");
            builder.begin_array();
            foreach (var folder in folders) {
                folder.value.to_json(builder);
            }
            builder.end_array();

            builder.set_member_name("files");
            builder.begin_array();
            foreach (var file in files) {
                file.value.to_json(builder);
            }
            builder.end_array();

            builder.end_object();
        }

    }

}