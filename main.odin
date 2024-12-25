package main

import "fsmon"
import "proxy"
import "core:thread"
import "core:fmt"

main :: proc() {
	fmt.print("Starting fsmon...")
	fsmon_dirname := cstring("./test_dir/")
	fsmon_thread := thread.create_and_start_with_data(transmute(rawptr) fsmon_dirname, fsmon.start)
	fmt.println(" Done!")

	fmt.println("Starting proxy...")
	proxy.start()

	thread.join(fsmon_thread)
}
