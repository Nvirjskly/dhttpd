module dhttpscript;

import std.regex, std.stdio, std.array;

enum EXPR_TYPE { NUMBER, STRING, VARIABLE, COMMAND};

struct Expr
{
	this(EXPR_TYPE type, string value)
	{
		this.type = type; this.value = value;
	}
	
	EXPR_TYPE type;
	string value;
}

struct ScriptRegex
{
	auto spaces = ctRegex!(`^[\n\t ]+`);
	auto string = ctRegex!("^`[^`]*`");
	auto number = ctRegex!(`^[0-9]+`); 
	auto variab = ctRegex!(`^\$[_a-zA-Z]+`);
	auto comman = ctRegex!(`^\![_a-zA-Z]+`);
	auto others = ctRegex!(`.`);  
}

void _script_main()
{
	string a = "`dhttpd` $server_name !let `error 404` !print $server_name !print"; 
	//auto m = a.match(ScriptRegex().number);
	//writeln(m.captures[0]);
	
	//writeln(parse(a));
	writeln(execute(parse(a)));
}

string dhttpScriptToString(string s)
{
	return execute(parse(s));
}

Expr[] parse(string s)
{
	Expr[] es;
	
	void parseReg()
	{
		writeln(""); 
		
	}
	
	while(s != "")
	{
		//Investigate if this is simpler to automate with a mixin
		//writeln("ZZZ");
		auto m = s.match(ScriptRegex().spaces);
		if(m) 
		{
			string cap = m.captures[0];
			//writeln(cap);
			s = s[cap.length .. s.length];
		}
		m = s.match(ScriptRegex().number);
		if(m)
		{
			string cap = m.captures[0];
			//writeln(cap);
			s = s[cap.length .. s.length];
			es ~= Expr(EXPR_TYPE.NUMBER,cap);
		}
		m = s.match(ScriptRegex().comman);
		if(m)
		{
			string cap = m.captures[0];
			//writeln(cap);
			s = s[cap.length .. s.length];
			es ~= Expr(EXPR_TYPE.COMMAND,cap);
		}
		m = s.match(ScriptRegex().variab);
		if(m)
		{
			string cap = m.captures[0];
			//writeln(cap);
			s = s[cap.length .. s.length];
			es ~= Expr(EXPR_TYPE.VARIABLE,cap);
		}
		m = s.match(ScriptRegex().string);
		if(m)
		{
			string cap = m.captures[0];
			
			//writeln(cap);
			s = s[cap.length .. s.length];
			cap.popFront();
			cap.popBack(); 
			es ~= Expr(EXPR_TYPE.STRING,cap);
		}
		m = s.match(ScriptRegex().others);
		if(m)
		{
			string cap = m.captures[0];
			//writeln(cap);
			s = s[cap.length .. s.length];
			
		}
	}
	return es;
}

string execute(Expr[] es)
{
	string ret = "";
	Expr[] stack;
	string[string] vars;
	vars["$_"] = "";
	
	string getVarNameFromStack()
	{
		Expr e = stack.back();
		stack.popBack();
		if (e.type == EXPR_TYPE.VARIABLE)
			return e.value;
		return "$_";
	}
	
	string getValueFromStack()
	{
		if (stack.length == 0)
		{
			return "";
		} else {
			Expr e = stack.back();
			stack.popBack();
			switch(e.type)
			{
				default:
					return "";
				break;
				
				case EXPR_TYPE.VARIABLE:
					string *a; a = (e.value in vars);
					if(a !is null)
						return vars[e.value];
					else
						return "";
				break;
			
				case EXPR_TYPE.NUMBER:
					return e.value;
				break;
			
				case EXPR_TYPE.STRING:
					return e.value;
				break;
				
			}
		}
	}
	
	for(uint i = 0; i < es.length; i++)
	{
		Expr e = es[i];
		switch(e.type)
		{
			default:
				
			break;
			
			case EXPR_TYPE.VARIABLE:
				stack ~= e;
			break;
			
			case EXPR_TYPE.NUMBER:
				stack ~= e;
			break;
			
			case EXPR_TYPE.STRING:
				stack ~= e;
			break;
			
			case EXPR_TYPE.COMMAND:
				switch(e.value)
				{
					default:
					
					break;
					
					case "!print":
						ret ~= getValueFromStack();
					break;
					
					case "!let":
						string a = getVarNameFromStack();
						string b = getValueFromStack();
						vars[a] = b;
					break;
				}
			break;
		}
	}
	return ret;
}