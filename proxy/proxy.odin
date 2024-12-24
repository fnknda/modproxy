package proxy

import "../modules"
import "socks4"
import "core:mem"
import "core:sys/linux"

Protocol :: enum { Socks4, Socks5 }

start_proxy :: proc(port: int = 1080, protocol: Protocol = .Socks4)
{
	sock, errno := linux.socket(.INET, .STREAM, {}, .TCP)
	assert(errno == .NONE)
	defer linux.close(sock)

	sockaddr: linux.Sock_Addr_In
	sockaddr.sin_family = .INET
	sockaddr.sin_port = 1080
	sockaddr.sin_addr = [4]u8{ 0, 0, 0, 0 }
	errno = linux.bind(sock, &sockaddr)
	assert(errno == .NONE)

	errno = linux.listen(sock, 1)
	assert(errno == .NONE)

	//TODO: Loop on accept for more than one client
	client: linux.Fd
	client_addr: linux.Sock_Addr_Any
	client, errno = linux.accept(sock, &client_addr, {})
	assert(errno == .NONE)

	request: socks4.Request
	buffer := mem.ptr_to_bytes(&request)
	bytes_read: int
	bytes_read, errno = linux.recvfrom(client, buffer, {}, &client_addr)
	assert(errno == .NONE)

	//FIXME: Instead of throwing panic at any error. Handle them.
	remote: linux.Fd
	remote, errno = linux.socket(.INET, .STREAM, {}, .TCP)
	assert(errno == .NONE)

	remote_addr: linux.Sock_Addr_In
	remote_addr.sin_family = .INET
	remote_addr.sin_port = request.dstport
	remote_addr.sin_addr = request.dstip
	errno = linux.connect(remote, &remote_addr)
	assert(errno == .NONE)

	response: socks4.Response
	if (request.cmd == .CONNECT) {
		response = {
			vn=0,
			rep=.GRANT,
			dstport=request.dstport,
			dstip=request.dstip,
		}
	}
	else {
		response = {
			vn=0,
			rep=.REJECT,
			dstport=request.dstport,
			dstip=request.dstip,
		}
	}

	buffer = mem.ptr_to_bytes(&response)
	bytes_sent: int
	bytes_sent, errno = linux.sendto(client, buffer, {}, &client_addr)
	assert(errno == .NONE)

	//TODO: Multithread this

	poll: linux.Fd
	poll, errno = linux.epoll_create()

	//FIXME: Error handling
	events := linux.EPoll_Event{ events=.IN|.HUP }

	events.data.fd = client
	linux.epoll_ctl(poll, .ADD, client, &events)

	events.data.fd = remote
	linux.epoll_ctl(poll, .ADD, remote, &events)

	con_loop: for {
		events := linux.EPoll_Event{}
		num_events: i32
		num_events, errno = linux.epoll_wait(poll, &events, 1, -1)

		fd_in, fd_out: linux.Fd

		buffer = make([]u8, 4096)
		addr := linux.Sock_Addr_In{}
		switch events.data.fd {
			case client:
				#partial switch events.events {
					case .IN:
						bytes_read, errno = linux.recvfrom(client, buffer, {}, &addr)
						if bytes_read > 0 {
							buffer = modules.run(.Send, client_addr, remote_addr, buffer[:bytes_read])
							bytes_sent, errno = linux.sendto(remote, buffer, {}, &remote_addr)
							continue
						}
						fallthrough
					case .HUP:
						break con_loop
				}
			case remote:
				#partial switch events.events {
					case .IN:
						bytes_read, errno = linux.recvfrom(remote, buffer, {}, &addr)
						if bytes_read > 0 {
							buffer = modules.run(.Receive, client_addr, remote_addr, buffer[:bytes_read])
							bytes_sent, errno = linux.sendto(client, buffer, {}, &client_addr)
							continue
						}
						fallthrough
					case .HUP:
						break con_loop
				}
		}
	}

	linux.close(client)
	linux.close(remote)
}
