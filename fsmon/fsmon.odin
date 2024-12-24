package fsmon

import "../modules"
import "core:slice"
import "core:strings"
import "core:sys/linux"
import "core:path/filepath"

start :: proc(dirname: string)
{
	//TODO: Check modules already in directory

	in_fd, errno := linux.inotify_init()
	assert(errno == .NONE)
	defer linux.close(in_fd)

	mask: linux.Inotify_Event_Mask = {
		.MOVED_FROM,
		.MOVED_TO,
		.CLOSE_WRITE,
		.DELETE,
		.ONLYDIR,
	}

	wd: linux.Wd
	wd, errno = linux.inotify_add_watch(in_fd, strings.unsafe_string_to_cstring(dirname), mask)
	assert(errno == .NONE)

	poll: linux.Fd
	poll, errno = linux.epoll_create()
	assert(errno == .NONE)

	events := linux.EPoll_Event{ events=.IN }
	errno = linux.epoll_ctl(poll, .ADD, in_fd, &events)
	assert(errno == .NONE)

	for {
		events := linux.EPoll_Event{}
		num_events: i32
		num_events, errno = linux.epoll_wait(poll, &events, 1, -1)
		assert(errno == .NONE)

		buffer : [size_of(events) + linux.NAME_MAX + 1]u8 = ---
		read_size: int
		read_size, errno = linux.read(in_fd, buffer[:])
		assert(errno == .NONE)

		for offset := 0; offset < read_size; {
			event := cast(^linux.Inotify_Event) &buffer[offset]
			name := string(slice.bytes_from_ptr(&event.name, int(event.len)))
			name = strings.truncate_to_byte(name, 0)
			path := filepath.join({ dirname, name })

			if .MOVED_TO in event.mask || .CLOSE_WRITE in event.mask {
				modules.add(path)
			}
			else if .MOVED_FROM in event.mask || .DELETE in event.mask {
				modules.remove(path)
			}

			offset += size_of(linux.Inotify_Event) + int(event.len)
		}
	}
}
