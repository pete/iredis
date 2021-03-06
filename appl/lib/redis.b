implement Redis;

include "sys.m"; sys: Sys;
include "draw.m";
include "dial.m"; dial: Dial;
include "arg.m";
include "bufio.m"; bufio: Bufio; Iobuf: import bufio;
include "string.m"; str: String;
include "redis.m";

debug: int;

initmod(s: Sys, d: Dial, b: Bufio, st: String) {
	sys = s;
	dial = d;
	bufio = b;
	str = st;

	debug = 0;
}

connect(addr: string): ref RedisClient {
	conn := dial->dial(addr, nil);
	if(conn == nil) {
		if(debug)
			sys->fprint(sys->fildes(2), "redis: dialing %s: %r\n", addr);
		return nil;
	}

	io := bufio->fopen(conn.dfd, bufio->ORDWR);
	if(io == nil)
		return nil;

	return client(io);
}

client(io: ref Iobuf): ref RedisClient {
	return ref RedisClient(io);
}

RedisClient.call(c: self ref RedisClient, cmd: list of string): list of (int, string) {
	if(!c.sendcmd(cmd))
		return nil;
	return c.parseresult();
}

setdebug(state: int) {
	debug = state;
}

# We make a few assumptions about what we'll have to cope with.  In
# particular, we expect to only parse atoms and arrays and we flatten all of the
# data we get back into a list of (tag, data) tuples, even if the data that
# comes back is not a list.
RedisClient.parseresult(cl: self ref RedisClient): list of (int, string) {
	r: list of (int, string) = nil;
	lt := array[256] of {
		'-' => RErr,
		':' => RInt,
		'+' => RStr,
		* => -1,
	};

	c := cl.io.getb();
	if(debug)
		sys->fprint(sys->fildes(2), "« %c", c);
	case c {
	'-' or ':' or '+' =>
		ln := chomp(cl.io.gets('\n'));
		r = (lt[c], ln) :: r;
	'$' => # String
		ln := cl.io.gets('\n');
		sz := str->toint(ln, 10).t0;
		if(debug)
			sys->fprint(sys->fildes(2), "%s\n", ln);
		if(sz == -1) {
			r = (RStr, nil) :: r;
		} else {
			r = (RStr, chomp(ln)) :: r;
		}
	'*' => # Array
		ln := cl.io.gets('\n');
		sz := str->toint(ln, 10).t0;
		for(i := sz; i > 0; i--) {
			nx := cl.parseresult();
			while(nx != nil) {
				r = hd nx :: r;
				nx = tl nx;
			}
		}
	* =>
		sys->fprint(sys->fildes(2), "lolwat: %d  %r\n", c);
		raise "fail:errors";
	}
	
	return rev2(r, nil);
}

RedisClient.printresult(cl: self ref RedisClient) {
	# Error:  -ERROR\r\n
	# Ints:  :NUMBER\r\n
	# Strings:  $size\r\nRAW\r\n *or* +RAW\r\n
	# Lists:  *size\r\nSTRING1 or INT1\r\n⋯\r\n
	c := cl.io.getb();
	if(debug)
		sys->fprint(sys->fildes(2), "« %c", c);
	
	if(c < 1) {
		sys->fprint(sys->fildes(2), "Connection dropped:  %r\n");
		raise "fail:errors";
	}
	case c {
	'-' or ':' or '+' =>
		ln := chomp(cl.io.gets('\n'));
		if(debug)
			sys->fprint(sys->fildes(2), "%s\n", ln);
		sys->print("%s\n", ln);
	'$' =>
		ln := cl.io.gets('\n');
		if(debug)
			sys->fprint(sys->fildes(2), "%s\n", ln);
		sz := str->toint(ln, 10).t0;
		if(sz < 0) {
			sys->print("(null)\n");
			return;
		}
		buf := array[sz + 2] of byte; # For the extra crlf.
		i := cl.io.read(buf, len buf);
		if(debug)
			sys->fprint(sys->fildes(2), "%s\n", string buf[:i]);
		s := chomp(string buf[:i]);
		sys->print("%s\n", s);
	'*' =>
		ln := cl.io.gets('\n');
		if(debug)
			sys->fprint(sys->fildes(2), "%s\n", ln);
		sz := str->toint(ln, 10).t0;
		if(sz < 0) {
			sys->print("(null)\n");
			return;
		}
		for(i := sz; i; i--)
			cl.printresult();
	* =>
		sys->fprint(sys->fildes(2), "Mystery response: %d  %r\n", c);
		raise "fail:errors";
	}
}

chomp(s: string): string {
	if(len s > 1 && s[len s - 1] == '\n' && s[len s - 2] == '\r')
		return s[:len s - 2];
	if(len s > 0 && s[len s - 1] == '\n')
		return s[:len s - 1];
	return s;
}

RedisClient.sendcmd(c: self ref RedisClient, cmd: list of string): int {
	cs := packcmd(cmd);
	if(debug)
		sys->fprint(sys->fildes(2), "» %s\n", cs);
	if(cs == nil)
		return 0;
	c.io.puts(cs);
	return 1;
}

packcmd(cmd: list of string): string {
	if(cmd == nil)
		return nil;
	r := sys->sprint("*%d\r\n", len cmd);
	while(cmd != nil) {
		s := hd cmd;
		cmd = tl cmd;
		r += sys->sprint("$%d\r\n%s\r\n", len array of byte s, s);
	}
	return r;
}

parsecmd(s: string, qc: int): (list of string, int) {
	r: list of string = nil;
	pendtick := 0;
	c := "";
	# Amateur hour.  Open mic night at an empty comedy club.
	# Needs a rewrite.  Don't read this loop.
	while(s != "") {
		if(pendtick) {
			if(s[0] == qc) {
				if(len s > 1 && s[1] == qc) {
					c[len c] = qc;
					s = s[1:];
				} else {
					r = c :: r;
					c = "";
					pendtick = 0;
				}
			} else {
				c[len c] = s[0];
			}
			s = s[1:];
		} else {
			if(s[0] == qc) {
				if(c != "") {
					sys->fprint(sys->fildes(2),
						"Syntax error:  unexpected \"%c\".\n", qc);
					return (nil, 0);
				}
				pendtick = 1;
			} else if(s[0] == ' ' || s[0] == '\t' || s[0] == '\n') {
				if(c != "")
					r = c :: r;
				c = "";
			} else {
				c[len c] = s[0];
			}
			s = s[1:];
		}
	}
	if(c != "")
		r = c :: r;
	return (rev(r, nil), !pendtick);
}

rev[T](s: list of T, a: list of T): list of T {
	if(s == nil)
		return a;
	return rev(tl s, hd s :: a);
}

rev2(s, a: list of (int, string)): list of (int, string) {
	if(s == nil)
		return a;
	return rev2(tl s, hd s :: a);
}

dl(s: list of string) {
	if(s == nil) {
		sys->fprint(sys->fildes(2), " ø\n");
		return;
	}
	sys->fprint(sys->fildes(2), "«%s» → ", hd s);
	dl(tl s);
}
