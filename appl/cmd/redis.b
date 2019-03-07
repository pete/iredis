implement RedisC;

include "sys.m"; sys: Sys;
include "draw.m";
include "dial.m"; dial: Dial;
include "arg.m";
include "bufio.m"; bufio: Bufio; Iobuf: import bufio;
include "string.m"; str: String;
include "redis.m"; redis: Redis;
	call, sendcmd, packcmd, parsecmd, printresult, parseresult: import redis;

RedisC: module {
	init: fn(nil: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args: list of string) {
	sys = load Sys Sys->PATH;
	dial = load Dial Dial->PATH;
	arg := load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	redis = load Redis Redis->PATH;
	if(redis == nil) {
		sys->fprint(sys->fildes(2), "Can't load %s! %r\n", Redis->PATH);
		raise "fail:load";
	}
	redis->initmod(sys, dial, bufio, str);

	arg->init(args);
	arg->setusage("redis [-i] [-a addr] [-d db#] [-e cmd] [-q chr]");

	addr := "tcp!localhost!6379";
	dbno := "0";
	cmd: list of string = nil;
	interactive := 0;
	quotechar := '"';

	while((opt := arg->opt()) != 0) {
		case opt {
		'a' =>
			addr = dial->netmkaddr(arg->earg(), "tcp", "6379");
		'd' =>
			dbno = arg->earg();
		'e' =>
			cmd = arg->earg() :: cmd;
		'i' =>
			interactive = 1;
		'h' =>
			arg->usage();
			return;
		'D' =>
			redis->setdebug(1);
		* =>
			arg->usage();
			raise "fail:usage";
		}
	}
	if(cmd == nil)
		interactive = 1;
	
	conn := dial->dial(addr, nil);
	if(conn == nil) {
		sys->fprint(sys->fildes(2), "redis: dialing %s: %r\n", addr);
		raise "fail:errors";
	}

	io := bufio->fopen(conn.dfd, bufio->ORDWR);
	if(io == nil)
		raise "fail:bufio";

	stdin := bufio->fopen(sys->fildes(0), bufio->OREAD);
	if(io == nil)
		raise "fail:bufio";

	# sys->fprint(sys->fildes(2), "redis: dialing %s, selecting %s\n", addr, dbno);
	selectdb(io, dbno);

	while(cmd != nil) {
		(ls, donep) := parsecmd(hd cmd, quotechar);
		if(!donep) {
			arg->usage();
			raise "fail:parse";
		}
		if(sendcmd(io, ls)) {
			cmd = tl cmd;
			printresult(io);
		}
	}
	if(!interactive)
		return;

	l := "";
	lu := array[2] of {'⋯', '>'};
	while(1) {
		sys->print("%s[%s]%c ", addr, dbno, lu[l == ""]);
		cl := stdin.gets('\n');
		if(cl == nil)
			return;
		l += cl;
		(ls, donep) := parsecmd(l, quotechar);
		if(donep) {
			l = "";
			if(sendcmd(io, ls))
				printresult(io);
		}
	}
}

selectdb(io: ref Iobuf, dbno: string) {
	sendcmd(io, parsecmd("SELECT " + dbno, 0).t0);
	printresult(io);
}
