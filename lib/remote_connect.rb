
# RemoteConnect - Ruby translation of Perl RemoteConnect
# Copyright 2000-5, The Regents of The University of Michigan, All Rights Reserved

require 'socket'

module RemoteConnect
  # Open a TCP socket to the given host and port, returning [writer, reader]
  def self.open(host, port)
    # Accept port as string or integer
    port = port.to_i
    sock = TCPSocket.new(host, port)
    # Set autoflush
    sock.sync = true
    # Return as [writer, reader] (same socket for both)
    [sock, sock]
  end
end
