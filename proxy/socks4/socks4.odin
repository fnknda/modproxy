package socks4

Request:: struct #packed {
	ver: u8,
	cmd: Command,
	dstport: u16be,
	dstip: [4]u8,
	id: struct #raw_union { [4096 - 8 ]u8, cstring },
}

Command:: enum u8 {
	CONNECT = 0x01,
	BIND = 0x02,
}

Response:: struct #packed {
	vn: u8,
	rep: Reply,
	dstport: u16be,
	dstip: [4]u8,
}

Reply:: enum u8 {
	GRANT = 0x5A,
	REJECT = 0x5B,
	NOIDENTD = 0x5C,
	NOCONFIRMID = 0x5D,
}
