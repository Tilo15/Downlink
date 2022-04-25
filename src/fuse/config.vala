
namespace DownlinkFuse {

    private string? get_item(string data, string key) {
        foreach (var line in data.split("\n")){
            var parts = line.split("=", 2);
            var name = parts[0].strip();
            if(name == key){
                return parts[1].strip();
            }
        }
        return null;
    }

    public class DownlinkConfig {

        public string mount_point { get; set; }

        public string cache_path { get; set; }

        public Gee.LinkedList<MountConfig> mounts { get; set; }

        public DownlinkConfig(string path) throws Error {
            string config_data;
            FileUtils.get_contents(path, out config_data, null);

            mount_point = get_item(config_data, "mountpoint") ?? "/downlink";
            cache_path = get_item(config_data, "cache") ?? "/var/downlink-cache";
            var mount_config = get_item(config_data, "mounts") ?? "/etc/downlink/mounts";

            var dir = Dir.open(mount_config);
            mounts = new Gee.LinkedList<MountConfig>();

            string? mount_file;
            while(null != (mount_file = dir.read_name())) {
                mounts.add(new MountConfig(@"$mount_config/$mount_file"));
            }

        }
    }

    public class MountConfig {

        public string name { get; set; }

        public string publisher_key { get; set; }

        public MountConfig(string path) throws Error {
            string config_data;
            FileUtils.get_contents(path, out config_data, null);

            name = get_item(config_data, "name");
            publisher_key = get_item(config_data, "key");

            if(name == null || publisher_key == null) {
                throw new Error(Quark.from_string("invalid-mount-config"), 53, @"The mount config at $(path) is missing either the mount name or publisher key.");
            }
        }

    }

}