
namespace Downlink.Util {

    public delegate void ByteBuilderDelegate(DataOutputStream stream) throws IOError ;

    public static uint8[] build_bytes(ByteBuilderDelegate builder) {

        var stream = new MemoryOutputStream(null, GLib.realloc, GLib.free);
        var dos = new DataOutputStream(stream);

        builder(dos);

        dos.flush();
        dos.close();
        uint8[] buffer = stream.steal_data();
        buffer.length = (int)stream.get_data_size();
        return buffer;
    }

    public static uint8[] string_to_bytes(string str) {
        return build_bytes(dos => dos.put_string(str));
    }

    public static string bytes_to_string(uint8[] bytes, bool null_terminate = true) {
        return new LibPeer.Util.ByteComposer().add_byte_array(bytes).to_string(null_terminate);
    }

}