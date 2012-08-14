// Written in the D programming language

/**
 * Author: Andrey A. Popov andrey.anat.popov@gmail.com
 */

module dhttpd;

import std.conv, std.socket, std.stdio, 
std.datetime, core.time, std.concurrency, core.sync.mutex, core.memory, core.bitop, core.thread, core.memory, std.range, std.stream, std.regex, std.string, std.file, std.random, std.process, std.variant;

import dhttpscript;
 
const string defaultConfig = 
"port = 80
wwwdir = C:\\dhttpd\\www

[ErrorFiles]
dir = C:\\dhttpd\\error
404 = \\error404.dhttps

";

enum SERVER_MESSAGES { START, RESET, SHUTDOWN, PAUSE }

//shared string serverDir;

class ListenServer
{
	struct response
	{
		header head;
		ubyte[] data;
	}
	struct header
	{
		uint status;
		string server = "dhttpd";
		ulong contentLength;
		string contentType;
		
		void parse(string h)
		{
			server = "dhttpd";
			
		}
		
		string toString()
		{
			string ret = "";
			ret ~= "HTTP/1.1 " ~httpStatusCode(status)~ "\nContent-Type: " ~ contentType ~ "; charset=UTF-8 \nServer: " ~ server ~ "\nConnection: close\nContent-Length: "~text(contentLength)~"\n\n";
			//writeString("HTTP/1.1 "~text(r.status)~" OK\nContent-Type: text/html; charset=UTF-8\nServer: dhttpd\nConnection: close\nContent-Length: "~text(sendMessage.length)~"\n\n");
		
			return ret;
		}
	}

	class Cache
	{
		struct fileData
		{
			ubyte[] data;
			ulong timestamp;
		}

		
		fileData[string] fileCache;
		
		this()
		{
			fileCache["error404"] = fileData();
			//fileCache["error404"].data = cast(ubyte[]) "error 404";
			string e404data = "";
			try
			{
				e404data = cast(string)read((serverConf.conf["ErrorFiles"]["dir"])~(serverConf.conf["ErrorFiles"]["404"]));
			} catch (Exception e) { e404data = "<h1>404 Not Found</h1>"; }
			fileCache["error404"].data = cast(ubyte[])e404data;
			fileCache["error404"].timestamp = Clock.currStdTime();
		}
		
		bool loadFileData(string fname)
		{
			ubyte[] data;
			try
			{
				if (fname.match(regex(`\.dhttps`)))
				{
					writeln("this is a dhttps file");
					//auto ft = fname.replace(`/`, "\\");
					string fileName = fname.replace(serverConf.conf["_main_"]["wwwdir"], "");
					string script = cast(string)read(fname);
					string scriptHead = "`" ~ fileName ~ "`" ~ " $filename !let ";
					string res = dhttpScriptToString(scriptHead ~ script);
					data = cast(ubyte[])res;
				}
				else
					data = cast(ubyte[]) read(fname);

				fileCache[fname] = fileData();
				fileCache[fname].data = data;
				fileCache[fname].timestamp = Clock.currStdTime();
				return true;
			} catch(Exception e) {
				writeln("error no such file " ~ fname);
				return false;
			}
		}
		
		response getFileData(string fn)
		{
			string fname = to!string(fn);
			fileData* a; a = (fname in fileCache); 
			response r;
			r.head = header();
			
			//writeln("Current time = " ~ text(Clock.currStdTime()));
			if ((a !is null && (Clock.currStdTime() - fileCache[fname].timestamp < 10000)) || loadFileData(fname))
			{
				r.head.status = 200;
				r.data = fileCache[fname].data;
				r.head.contentType = mimeTypeByName(fname);
			} else {
				r.head.status = 404;
				string fileName = fname.replace(serverConf.conf["_main_"]["wwwdir"], "");
				string scriptHead = "`" ~ fileName ~ "`" ~ " $filename !let ";
				r.data = cast(ubyte[])dhttpScriptToString(scriptHead ~ cast(string)fileCache["error404"].data);
				r.head.contentType = "text/html";
			}
			r.head.contentLength = r.data.length;
			//writeln(r);
			return r;
		}
	}

	private Mutex _listenerMutex;
	private Mutex _socksMutex;
	private ushort _port;
	private TcpSocket _listener;
	private Socket[] _socks;
	private Cache _cache;
	private Mutex _cacheMutex;
	private string _serverDir;
	Config serverConf;
	
	Tid loopThread;
	Tid controlThread;
	Tid cacheThreadTid;
	
	
	this()
	{
		_script_main();
		serverConf = Config();
	
		serverConf.parse(defaultConfig);
		serverConf.parseFile("dhttpd_config.ini");
		writeln(serverConf.conf);
		_port = to!ushort(serverConf.conf["_main_"]["port"]);
		_serverDir = serverConf.conf["_main_"]["wwwdir"];
	
		_cache = new Cache();
		_cacheMutex = new Mutex();
		_listenerMutex = new Mutex();
		_socksMutex = new Mutex();
		
	}
	void setup()
	{	
		_listenerMutex.lock();
			_listener = new TcpSocket();
			assert(_listener.isAlive);
			_listener.blocking = false;
			_listener.bind(new InternetAddress(_port));
			_listener.listen(10);
			writefln("Listening on port %d.", _port);
		_listenerMutex.unlock();

		auto listenT = new core.thread.Thread(&listenThread);
		listenT.start();
		
		auto interT = new core.thread.Thread(&interactThread);
		interT.start();
	}
	response getFromCache(string fname) 
	{
		_cacheMutex.lock();
		shared string fn = fname;
		response r = _cache.getFileData(fn);
		_cacheMutex.unlock();
		return r;
	}
	
	void listenThread()
	{
		int SERVER_STATUS = SERVER_MESSAGES.PAUSE;
		const core.time.Duration un = to!(core.time.Duration)(core.time.TickDuration(1));
		const uint fps = 500;
		const auto wait = TickDuration.ticksPerSec / fps;
		auto timer = StopWatch(AutoStart.yes);
		while(SERVER_STATUS != SERVER_MESSAGES.SHUTDOWN)
		{	
			//writeln(uniform(0x0,0x111));

			/*receiveTimeout
			(
				un,
				(SERVER_MESSAGES i)
				{
					SERVER_STATUS = i;
				}
			);*/

			//SERVER_STATUS = SERVER_MESSAGES.START;
			//if(SERVER_STATUS == SERVER_MESSAGES.START)
			try{
				listen(); 
			} catch (Exception e)
			{
				writeln(e);
			}
			long wf = wait-timer.peek().length;
			if (wf > 0)
				core.thread.Thread.sleep(to!(core.time.Duration)(TickDuration(wf)));
			timer.reset();
			
		}
	}
	void interactThread()
	{
		const uint fps = 500;
		const auto wait = TickDuration.ticksPerSec / fps;
		auto timer = StopWatch(AutoStart.yes);
		
		while(1)
		{
			_listenerMutex.lock();
			interActWithSocket();
			_listenerMutex.unlock();
			long wf = wait-timer.peek().length;
			if (wf > 0)
				core.thread.Thread.sleep(to!(core.time.Duration)(TickDuration(wf)));
			timer.reset();
		}
	}
	
	void listen()
	{
		//writeln("l");
		Socket clientSocket;
		//_listenerMutex.lock();
		clientSocket = _listener.accept();
		//_listenerMutex.unlock();
		if(clientSocket.isAlive() && !clientSocket.blocking())
		{
			writeln("Connected To " ~ clientSocket.remoteAddress().toString());
			
			_socksMutex.lock();
				_socks ~= clientSocket;	
			_socksMutex.unlock();

		} else {
			//write("f");
			//clientSocket.shutdown(SocketShutdown.BOTH);
			clientSocket.close();
		}
	}
	void interActWithSocket()
	{
		Socket clientSocket;
		string readToString()
		{
			string str = "";
			char[1024] _buf;
			char[] buf;
			ptrdiff_t l = 0;
			uint la = 0;
			do
			{
				try{
				if(!clientSocket.blocking())
					l = clientSocket.receive(_buf);
				} catch(Exception e)
				{ writeln(e);}
				//writeln(l);
				if (l > 0)
				{
					buf ~= _buf[0 .. l];
					la += l;
				}
			} while(l > 0);
			for(uint i = 0; i < la; i++)
				str ~= to!string(buf[i]);
			return str;
		}
			
		void writeString(string str)
		{
			try
			{
			if(!clientSocket.blocking())
				clientSocket.send(cast(ubyte[])str);
			} catch (Exception e)
			{ writeln(e);}
		}
		
		void writeUbytes(ubyte[] str)
		{
			try
			{
			if(!clientSocket.blocking())
				clientSocket.send(str);
			} catch (Exception e)
			{ writeln(e);}
		}
	
		_socksMutex.lock();
		//writeln(_socks.length);
		while(_socks.length > 0)
		{
			//writeln(_socks.length);
			clientSocket = _socks.front();
			
			//writeln(parseRequestHeaders(readToString()));
			
			string fname = parseRequestHeaders(readToString());
			writeString("HTTP/1.1 100 continue\n\n");
			writeln(fname);
			if(fname.back == '/')
				fname ~= "index.html";
			
			ubyte[] sendMessage = [];

			response r = getFromCache(_serverDir ~ fname);
			
			sendMessage = r.data;
			
			try{
				
				//writeString("HTTP/1.1 "~text(r.status)~" OK\nContent-Type: text/html; charset=UTF-8\nServer: dhttpd\nConnection: close\nContent-Length: "~text(sendMessage.length)~"\n\n");
				//writeln(r.head.toString());
				writeString(r.head.toString());
			}catch(Exception e) { writeln(e);}

			//writeString(sendMessage);
			writeUbytes(sendMessage);

			clientSocket.close();
			_socks.popFront();

		}
		_socksMutex.unlock();
	}
	
	string parseRequestHeaders(string header)
	{
		string[string] flags;
		auto hs = header.split("\n");
		if(hs.length != 0)
		{
			//writeln("DIS SHIT HIT DA FAN");
			string requestType = hs.front();
			hs.popFront();
				
			foreach(h; hs)
			{
				auto head = h.split(":");
				//if(head.length == 2)
				//	flags[strip(head[0])] = strip(head[1]);
			}
			return (requestType.split(" ")[1]).split("?")[0];
		} else {
			return "/";
		}
	}
}

private ListenServer s;
private Mutex _listenServerMutex;

void main(string[] args)
{
	//if(fork())
	//	exit(0);
	_listenServerMutex = new Mutex();
	
	_listenServerMutex.lock();
		s = new ListenServer();
		s.setup();
	_listenServerMutex.unlock();
	
	const uint fps = 1;
	const auto wait = TickDuration.ticksPerSec / fps;
	auto timer = StopWatch(AutoStart.yes);
	while(1)
	{	
		//core.thread.Thread.sleep(to!(core.time.Duration)(TickDuration(5*(wait-timer.peek().length))));	
		//Do nothing really...
		if ( (timer.peek().length+10) < wait )
			core.thread.Thread.sleep(to!(core.time.Duration)(TickDuration(wait-timer.peek().length)));
		timer.reset();
	}
}

private void controlLoop(Tid serverTid, ushort port)
{
	//uint controlPort = 54678;
	
	//Socket controlSocketListener = new TcpSocket(new InternetAddress("localhost", port));
	
	Socket controlSocketListener = new TcpSocket;
	assert(controlSocketListener.isAlive);
	controlSocketListener.blocking = false;
	controlSocketListener.bind(new InternetAddress(port));
	controlSocketListener.listen(1000);
	
	const uint fps = 10;
	const auto wait = TickDuration.ticksPerSec / fps;
	auto timer = StopWatch(AutoStart.yes);
	while(1)
	{
		Socket controlSocket = controlSocketListener.accept();
		if(controlSocket.isAlive())
		{
			writeln("zzz");
			spawn(&controlConnection, serverTid, cast(shared)controlSocket);
		}
		
		while ( timer.peek().length < wait )
			core.thread.Thread.sleep(to!(core.time.Duration)(TickDuration(wait-timer.peek().length)));
		timer.reset();
	}
}

private void controlConnection(Tid serverTid, shared Socket controlSocket)
{
	Socket sock = cast(Socket)controlSocket;
	//ConnectionEncryption ce = new ConnectionEncryption(sock);
	
	string message = "";
	
	//while (message == "")
		//message = ce.receiveMessage();
	
	writeln("message: " ~ message);
}

/**
 * Takes a file name as input and tries t return the appropriate mime type.
 */
string mimeTypeByName(string fname)
{
	string type = fname.split(".").back();
	
	switch(type)
	{
		default:
			return "text/plain";
		break;
		
		case "js":
			return "application/javascript";
		break;
		
		case "htm":
			return "text/html";
		break;
		
		case "html":
			return "text/html";
		break;
		
		case "zip":
			return "application/zip";
		break;
		
		case "png":
			return "image/png";
		break;
		
		case "jpg":
			return "image/jpeg";
		break;
		
		case "jpeg":
			return "image/jpeg";
		break;
		
		case "d":
			return "text/x-d";
		break;
		
		case "dhttps":
			return "text/html";
		break;
	}
}

/**
 * Takes a staus code integer as input and returns the appropriate HTTP status code.
 */
string httpStatusCode(uint i)
{
	switch(i)
	{
		default: 
			return "100 Continue";
		break;
		
		case 200:
			return "200 OK";
		break;
		
		case 404:
			return "404 File Not Found";
		break;
	}
	
}

/**
 * Config structure 
 * [section]
 * ;comment
 * name=value
 */

struct Config
{
	string[string][string] conf;
	void parseFile(string fname)
	{
		try
		{
			parse(cast(string)read(fname));
		} catch (Exception e)
		{ writeln("Configuration File "~fname~" not found."); }
	}
	void parse(string datum)
	{
		auto data = datum.split("\n");
		string currentSection = "_main_";
		for(uint i = 0; i < data.length; i++)
		{
			string line = strip(data[i]);
			if (line.length > 0)
			{
				switch(line.front())
				{
					default:
						auto vals = line.split("=");
						if (vals.length < 2)
							conf[currentSection][vals.front()] = "1";
						else
						{
							string name = strip(vals.front());
							vals.popFront();
							conf[currentSection][name] = strip(vals.join());
						}
					break;
					
					case ';':
						//comment; do nothing
					break;
					
					case '['://section
						line.popFront();
						if (line.back() == ']')
							line.popBack();
						currentSection = line;
					break;
				}
			}
		}
	}
}