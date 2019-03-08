# This interface should not be considered stable.  See the documentation.
Redis: module {
	PATH: con "/dis/lib/redis.dis";

	initmod: fn(s: Sys, d: Dial, b: Bufio, st: String);
	call: fn(io: ref Iobuf, cmd: list of string): list of (int, string);
	sendcmd: fn(io: ref Iobuf, cmd: list of string): int;
	packcmd: fn(cmd: list of string): string;
	parsecmd: fn(s: string, qc: int): (list of string, int);
	printresult: fn(io: ref Iobuf);
	parseresult: fn(io: ref Iobuf): list of (int, string);

	RStr, RInt, RErr: con iota + 1;

	setdebug: fn(state: int);
};
