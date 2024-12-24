package modules

import "core:fmt"
import "core:strings"
import "core:sys/posix"
import "core:sys/linux"

modules: [dynamic]Module

Operation :: enum {
	Connect,
	Disconnect,
	Send,
	Receive,
}

Module :: struct {
	path: string,
	dl: posix.Symbol_Table,
	priority: int,
	on_connect: proc "c" (client: linux.Sock_Addr_In, remote: linux.Sock_Addr_In, data: []u8) -> []u8,
	on_disconnect: proc "c" (client: linux.Sock_Addr_In, remote: linux.Sock_Addr_In, data: []u8) -> []u8,
	on_send: proc "c" (client: linux.Sock_Addr_In, remote: linux.Sock_Addr_In, data: []u8) -> []u8,
	on_receive: proc "c" (client: linux.Sock_Addr_In, remote: linux.Sock_Addr_In, data: []u8) -> []u8,
}

add_path :: proc(path: string)
{
	dl := posix.dlopen(strings.unsafe_string_to_cstring(path), {.NOW})
	assert(dl != nil)

	fmt.println("open")
	dl_get_priority := (proc "c" () -> int) (posix.dlsym(dl, "get_priority"))
	fmt.println("sym")
	assert(dl_get_priority != nil)

	module := Module {
		path = path,
		dl = dl,
		priority = dl_get_priority(),
		on_connect = (proc "c" (client: linux.Sock_Addr_In, remote: linux.Sock_Addr_In, data: []u8) -> []u8)(posix.dlsym(dl, "on_connect")),
		on_disconnect = (proc "c" (client: linux.Sock_Addr_In, remote: linux.Sock_Addr_In, data: []u8) -> []u8)(posix.dlsym(dl, "on_disconnect")),
		on_send = (proc "c" (client: linux.Sock_Addr_In, remote: linux.Sock_Addr_In, data: []u8) -> []u8)(posix.dlsym(dl, "on_send")),
		on_receive = (proc "c" (client: linux.Sock_Addr_In, remote: linux.Sock_Addr_In, data: []u8) -> []u8)(posix.dlsym(dl, "on_receive")),
	}

	add_module(module)
}

add_module :: proc(module: Module)
{
	fmt.println("Adding module", module)

	idx := 0
	for mod in modules {
		if mod.priority > module.priority {
			break
		}
		idx += 1
	}

	inject_at(&modules, idx, module)
}

add :: proc{add_path, add_module}

remove_path :: proc(path: string)
{
	fmt.println("Removing module", path)
	//TODO: Implement module removal
}

remove :: proc{remove_path}

run :: proc(op: Operation, client: linux.Sock_Addr_In, remote: linux.Sock_Addr_In, data: []u8) -> []u8
{
	data := data

	for mod in modules {
		switch op {
			case .Connect:
				if mod.on_connect != nil do data = mod.on_connect(client, remote, data)
			case .Disconnect:
				if mod.on_disconnect != nil do data = mod.on_disconnect(client, remote, data)
			case .Send:
				if mod.on_send != nil do data = mod.on_send(client, remote, data)
			case .Receive:
				if mod.on_receive != nil do data = mod.on_receive(client, remote, data)
		}
	}

	return data
}
