package main

import "fsmon"
import "proxy"

main :: proc() {
	//TODO: Multithreading to run the whole program concurrently
	fsmon.start("./test_dir/")
}
