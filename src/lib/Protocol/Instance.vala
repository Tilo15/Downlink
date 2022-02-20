using LibPeer.Protocols.Mx2;
using LibPeer.Protocols.Stp;
using LibPeer.Protocols.Stp.Streams;
using LibPeer.Util;

namespace Downlink {

    public class Instance : Object {

        private Gee.LinkedList<CommandingPeer> commanding_peers = new Gee.LinkedList<CommandingPeer>();

        private StreamTransmissionProtocol stp;

        private Store store;

        public Instance(StreamTransmissionProtocol transport, Store cache) {
            store = cache;
            stp = transport;
        }

        public void handle_stream(StpInputStream stream) {
            var magic = new uint8[1];
            stream.read(magic);
            if(magic[0] == 'I') {
                commanding_peers.add(new CommandingPeer(stream, stp));
                return;
            }
            stream.close();
        }

        public void service_peers() {
            foreach (var peer in commanding_peers) {
                if(!peer.pending_command) { continue; }
                var command = peer.get_next_command();

                if(command[0] == "METADATA") {
                    print("Metadata request\n");
                    var key = new PublisherKey.from_string(command[1].split(" ")[0]);
                    if(!store.has_metadata(key)) {
                        print("We don't have that metadata :(\n");
                        peer.reply_stream.put_byte((uint8)CommandStatus.NO_METADATA);
                    }
                    else {
                        Metadata metadata;
                        if(store.try_read_metadata(out metadata, key)) {
                            print("Read metadata.\n");
                            peer.reply_stream.put_byte((uint8)CommandStatus.OK);
                            print("Sending metadata.\n");
                            var metadata_bytes = metadata.to_bytes();
                            peer.reply_stream.put_uint32(metadata_bytes.length);
                            peer.reply_stream.write(metadata_bytes);
                            print("Metadata sent.\n");
                        }
                        else {
                            print("Internal error.\n");
                            peer.reply_stream.put_byte((uint8)CommandStatus.INTERNAL_ERROR);
                        }
                    }
                }

                else if(command[0] == "PROBE") {

                    var identifier = new ResourceIdentifier.from_string(command[1].split(" ")[0]);
                    if(store.has_full_resource(identifier)) {
                        peer.reply_stream.put_byte((uint8)CommandStatus.OK);
                        // Length of response data, reserved for future use.
                        peer.reply_stream.put_uint64(0);
                    }
                    else {
                        peer.reply_stream.put_byte((uint8)CommandStatus.NOT_FOUND);
                    }

                }

                else if(command[0] == "AUTH") {
                    print("Read auth table.\n");
                    var identifier = new ResourceIdentifier.from_string(command[1].split(" ")[0]);
                    if(store.has_full_resource(identifier)) {
                        print("I have the auth table.\n");
                        AuthTable auth_table;
                        if(store.try_read_auth_table(out auth_table, identifier)) {
                            peer.reply_stream.put_byte((uint8)CommandStatus.OK);
                            peer.reply_stream.write(auth_table.serialise());
                        }
                        else {
                            print("Error reading auth table\n");
                            peer.reply_stream.put_byte((uint8)CommandStatus.INTERNAL_ERROR);
                        }
                    }
                    else {
                        print("I didn't have that auth table\n");
                        peer.reply_stream.put_byte((uint8)CommandStatus.NOT_FOUND);
                    }

                }
                
                else if(command[0] == "GET") {

                    var parts = command[1].split(" ");
                    var identifier = new ResourceIdentifier.from_string(parts[0]);
                    var start = uint64.parse(parts[1]);
                    var end = uint64.parse(parts[2]);

                    if(!store.has_full_resource(identifier)) {
                        peer.reply_stream.put_byte((uint8)CommandStatus.NOT_FOUND);
                    }
                    else if(end > identifier.size) {
                        peer.reply_stream.put_byte((uint8)CommandStatus.OUT_OF_RANGE);
                    }
                    else {
                        uint8[] data;
                        if(store.try_read_resource(out data, identifier, start, end)) {
                            peer.reply_stream.put_byte((uint8)CommandStatus.OK);
                            print(@"Sending all $(data.length) bytes read from cache as reply to request asking for $(end - start) bytes.\n");
                            peer.reply_stream.write(data);
                        }
                        else {
                            peer.reply_stream.put_byte((uint8)CommandStatus.INTERNAL_ERROR);
                        }
                    }

                }
                else {
                    peer.reply_stream.put_byte((uint8)CommandStatus.UNRECOGNISED_COMMAND);
                }
                
                peer.reply_stream.flush();
                
            }
        }

    }

    private class CommandingPeer {
        public StpInputStream underlying_command_stream;
        public DataInputStream command_stream { get; set; }
        public DataOutputStream reply_stream { get; set; }
        public InstanceReference instance_reference { get; set; }

        public CommandingPeer(StpInputStream stream, StreamTransmissionProtocol stp) {
            underlying_command_stream = stream;
            command_stream = new DataInputStream(stream);
            command_stream.buffer_size = 1;
            instance_reference = stream.origin;
            stp.initialise_stream(instance_reference, stream.session_id).established.connect(s => reply_stream = new DataOutputStream(s));
        }

        public string[] get_next_command() {
            print("Reading command\n");
            
            var command = command_stream.read_upto(" ", 1, null);
            command_stream.read_byte();
            var arguments = command_stream.read_upto("\n", 1, null);
            command_stream.read_byte();

            print(@"Recieve: $(command) $(arguments)\n");
            print("Yeah\n");
            return new string[] {
                command,
                arguments
            };
        }

        public bool pending_command {
            get { return true; }
        }
    }

}