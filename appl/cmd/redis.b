implement RedisC;

include "sys.m"; sys: Sys;
include "draw.m";
include "dial.m"; dial: Dial;
include "arg.m";
include "bufio.m"; bufio: Bufio; Iobuf: import bufio;
include "string.m"; str: String;
include "redis.m"; redis: Redis;
	RedisClient, packcmd, parsecmd: import redis;

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

	debug := 0;

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
		'q' =>
			quotechar = arg->earg()[0];
			if(quotechar == 0) {
				arg->usage();
				raise "fail:usage";
			}
		'h' =>
			arg->usage();
			return;
		'D' =>
			debug = 1;
		* =>
			arg->usage();
			raise "fail:usage";
		}
	}
	if(cmd == nil)
		interactive = 1;
	redis->setdebug(debug);

	c := redis->connect(addr);
	if(c == nil) {
		sys->fprint(sys->fildes(2), "redis: connecting to %s: %r\n", addr);
		raise "fail:errors";
	}

	stdin := bufio->fopen(sys->fildes(0), bufio->OREAD);
	if(stdin == nil)
		raise "fail:bufio";

	if(debug)
		sys->fprint(sys->fildes(2), "redis: dialing %s, selecting %s\n", addr, dbno);
	selectdb(c, dbno);

	cmd = rev(cmd);

	while(cmd != nil) {
		(ls, donep) := parsecmd(hd cmd, quotechar);
		if(!donep) {
			arg->usage();
			raise "fail:parse";
		}
		if(c.sendcmd(ls)) {
			cmd = tl cmd;
			c.printresult();
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
			if(c.sendcmd(ls))
				c.printresult();
		}
	}
}

selectdb(c: ref Redis->RedisClient, dbno: string) {
	c.sendcmd(parsecmd("SELECT " + dbno, 0).t0);
	c.printresult();
}

rev[T](s: list of T): list of T {
	r: list of T = nil;
	while(s != nil) {
		r = hd s :: r;
		s = tl s;
	}
	return r;
}
