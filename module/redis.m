# This interface should not be considered stable.  See the documentation.
Redis: module {
	PATH: con "/dis/lib/redis.dis";

	initmod: fn(s: Sys, d: Dial, b: Bufio, st: String);
	connect: fn(addr: string): ref RedisClient;
	client: fn(io: ref Iobuf): ref RedisClient;

	parsecmd: fn(s: string, qc: int): (list of string, int);
	packcmd: fn(cmd: list of string): string;

	RStr, RInt, RErr: con iota + 1;

	setdebug: fn(state: int);

	RedisClient: adt {
		call: fn(c: self ref RedisClient, cmd: list of string): list of (int, string);

		# You probably won't need these:
		sendcmd: fn(c: self ref RedisClient, cmd: list of string): int;
		printresult: fn(c: self ref RedisClient);
		parseresult: fn(c: self ref RedisClient): list of (int, string);

		# Internal:
		io: ref Bufio->Iobuf;
	};
};
