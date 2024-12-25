package proxy

import "socks4"
import "../modules"
import "core:mem"
import "core:fmt"
import "core:thread"
import "core:sys/linux"

handle_client:: proc(raw_client: rawptr)
{
	client := cast(linux.Fd)uintptr(raw_client)
	defer linux.close(client)

	fmt.println("File descriptor:", client)

	client_addr: linux.Sock_Addr_Any

	request: socks4.Request
	buffer := mem.ptr_to_bytes(&request)
	bytes_read, errno := linux.recvfrom(client, buffer, {}, &client_addr)
	assert(errno == .NONE)

	fmt.println("Attempting to connect,", request)

	could_connect := true

	remote: linux.Fd
	remote, errno = linux.socket(.INET, .STREAM, {}, .TCP)
	if errno != .NONE do could_connect = false
	defer linux.close(remote)

	remote_addr: linux.Sock_Addr_In
	remote_addr.sin_family = .INET
	remote_addr.sin_port = request.dstport
	remote_addr.sin_addr = request.dstip
	errno = linux.connect(remote, &remote_addr)
	if errno != .NONE do could_connect = false

	response: socks4.Response
	if could_connect && request.cmd == .CONNECT {
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

	if response.rep == .REJECT do return

	poll: linux.Fd
	poll, errno = linux.epoll_create()
	assert(errno == .NONE)

	events := linux.EPoll_Event{ events=.IN|.HUP }

	events.data.fd = client
	errno = linux.epoll_ctl(poll, .ADD, client, &events)
	assert(errno == .NONE)

	events.data.fd = remote
	errno = linux.epoll_ctl(poll, .ADD, remote, &events)
	assert(errno == .NONE)

	con_loop: for {
		events := linux.EPoll_Event{}
		num_events: i32
		num_events, errno = linux.epoll_wait(poll, &events, 1, -1)
		assert(errno == .NONE)

		fd_in, fd_out: linux.Fd

		buffer = make([]u8, 4096)
		addr := linux.Sock_Addr_In{}
		switch events.data.fd {
			case client:
				#partial switch events.events {
					case .IN:
						bytes_read, errno = linux.recvfrom(client, buffer, {}, &addr)
						assert(errno == .NONE)
						if bytes_read > 0 {
							buffer = modules.run(.Send, client_addr, remote_addr, buffer[:bytes_read])
							bytes_sent, errno = linux.sendto(remote, buffer, {}, &remote_addr)
							assert(errno == .NONE)
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
						assert(errno == .NONE)
						if bytes_read > 0 {
							buffer = modules.run(.Receive, client_addr, remote_addr, buffer[:bytes_read])
							bytes_sent, errno = linux.sendto(client, buffer, {}, &client_addr)
							assert(errno == .NONE)
							continue
						}
						fallthrough
					case .HUP:
						break con_loop
				}
		}
	}
}

start :: proc(port: u16be = 1080)
{
	sock, errno := linux.socket(.INET, .STREAM, {}, .TCP)
	assert(errno == .NONE)
	defer linux.close(sock)

	sockaddr: linux.Sock_Addr_In
	sockaddr.sin_family = .INET
	sockaddr.sin_port = port
	sockaddr.sin_addr = [4]u8{ 0, 0, 0, 0 } //TODO: Allow changing where to bind to
	errno = linux.bind(sock, &sockaddr)
	assert(errno == .NONE)

	errno = linux.listen(sock, 1)
	assert(errno == .NONE)

	fmt.println("Waiting for clients")
	for {
		client: linux.Fd
		client_addr: linux.Sock_Addr_Any
		client, errno = linux.accept(sock, &client_addr, {})
		assert(errno == .NONE)

		thread.create_and_start_with_data(transmute(rawptr)uintptr(client), handle_client)
	}
}
