
namespace DownlinkKeygen {

    public static int main(string[] args) {

        if(args.length < 2) {
            printerr("Usage: downlink-keygen <output file>\nGenerates a new publishing key for signing Downlink metadata\n");
            return -1;
        }

        var key = new Downlink.PublishingKey();

        var file = File.new_for_path(args[1]);
        if(file.query_exists()) {
            printerr("Did not create new key: file exists.\n");
            return -2;
        }
        var dos = new DataOutputStream(file.create(FileCreateFlags.REPLACE_DESTINATION));
        dos.put_string(@"$key\n");
        dos.close();

        return 0;

    }

}