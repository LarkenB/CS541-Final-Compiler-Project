%{
#include <iostream> // cerr, cout
#include <algorithm> // reverse
#include "types.h"
using namespace clukcs;

/* Prototype for a function defined by flex. */
void yylex_destroy();

void yyerror(const std::string msg)
{
	std::cerr << msg << '\n';
}

void yyerror(const char *msg)
{
	std::cerr << msg << '\n';
}

// The unique global symbol table.
symbol_table symtab;

std::string get_llvm_type(const Type type) {
	switch(type) {
  		case Type::Int:
  		  return "i32";
  		case Type::Float:
  		  return "float";
		case Type::Char:
  		  return "i8";
  		default:
			return "UNKNOWN";
	}
}

Address* cast_to_lhs_type(Type lhs_type, Address* rhs, parser_val& current) {
	if (lhs_type == Type::Unknown || rhs == nullptr || rhs->type() == Type::Unknown) {
		yyerror("ERROR: CANNOT CAST VARIABLE WITH TYPE 'UNKNOWN'");
		return nullptr; // MAYBE CLEANER TO RETURN LHS?
	}

	if (lhs_type == rhs->type()) {
		return rhs; // MAY NEED TEMP HERE INSTEAD
	}

	switch (lhs_type) {
		case Type::Int: {
			auto temp = symtab.make_temp(Type::Int);

			// Generate casting code
			if (rhs->type() == Type::Float) 
				current.code += "  " + temp->name() + " = fptosi float " + rhs->name() + " to i32\n";
			else if (rhs->type() == Type::Char) 
				current.code += "  " + temp->name() + " = sext i8 " + rhs->name() + " to i32\n";

  			return temp;
		}
  		case Type::Float: {
			auto rhs_llvm_type = get_llvm_type(rhs->type());
			auto temp = symtab.make_temp(Type::Float);

			current.code += "  " + temp->name() + " = sitofp " + rhs_llvm_type + " " + rhs->name() + " to float\n";

  			return temp;
		}
		case Type::Char: {
			auto temp = symtab.make_temp(Type::Char);

			// Generate casting code
			if (rhs->type() == Type::Float) 
				current.code += "  " + temp->name() + " = fptosi float " + rhs->name() + " to i8\n";
			else if (rhs->type() == Type::Int) 
				current.code += "  " + temp->name() + " = trunc i32 " + rhs->name() + " to i8\n";

  			return temp;
		}
		default: {
			yyerror("ERROR: CANNOT CAST VARIABLE TO TYPE 'UNKNOWN'");
			return nullptr;
		}
	}

	yyerror("ERROR: CANNOT CAST VARIABLE WITH TYPE 'UNKNOWN'");
	return nullptr;
}

bool cast_for_binop(Address*& lhs, Address*& rhs, parser_val& current) {
	if (lhs == nullptr || lhs->type() == Type::Unknown || rhs == nullptr || rhs->type() == Type::Unknown) {
		yyerror("ERROR: CANNOT CAST VARIABLE WITH TYPE 'UNKNOWN'");
		return false;
	}

	// Apply conversions if needed
	if (lhs->type() != rhs->type()) {
		if (lhs->type() == Type::Float) {
			// Convert rhs to float
			auto rhs_llvm_type = get_llvm_type(rhs->type());
			auto temp = symtab.make_temp(Type::Float);

			current.code += "  " + temp->name() + " = sitofp " + rhs_llvm_type + " " + rhs->name() + " to float\n";
			rhs = temp;
			return true;
		} else if (rhs->type() == Type::Float) {
			// Convert lhs to float
			auto lhs_llvm_type = get_llvm_type(lhs->type());
			auto temp = symtab.make_temp(Type::Float);

			current.code += "  " + temp->name() + " = sitofp " + lhs_llvm_type + " " + lhs->name() + " to float\n";
			lhs = temp;
			return true;
		} else if (lhs->type() == Type::Int) {
			// Convert rhs from char to int
			auto temp = symtab.make_temp(Type::Int);

			current.code += "  " + temp->name() + " = sext i8 " + rhs->name() + " to i32\n";
			rhs = temp;
			return true;
		} else if (rhs->type() == Type::Int) {
			// Convert lhs from char to int
			auto temp = symtab.make_temp(Type::Int);

			current.code += "  " + temp->name() + " = sext i8 " + lhs->name() + " to i32\n";
			lhs = temp;
			return true;
		} else {
			yyerror("ERROR: CANNOT CAST VARIABLE WITH TYPE 'UNKNOWN'");
			return false;
		}
	} else {
		// Have the same type, so casting is not needed
		return true;
	}
}

%}

/* Put this into the generated header file, too */
%code requires {
  #include "types.h"
  #include "globals.h"
}

/* Semantic value for grammar symbols.  See definition in types.h */
%define api.value.type { clukcs::parser_val }

%token IDENTIFIER INT_LITERAL FLOAT_LITERAL CHAR_LITERAL UMINUS
%token '+' '-' '*' '/' '%' '=' '(' ')' '{' '}' ';' INT FLOAT CHAR RETURN


/* Which nonterminal is at the top of the parse tree? */
%start program

/* Precedence */
%right '='
%left '+' '-'
%left '*' '/' '%'
%left UMINUS

%%

program: statement_list {
	auto header = 
		"target datalayout = \"e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128\"\n"
		"target triple = \"x86_64-pc-linux-gnu\"\n\n"
		"define dso_local i32 @main() {\n";

	auto footer = "}";

	// Check for return statement, add one if needed
	if ($1.code.length() > 0) {
		auto rev_code = std::string($1.code.rbegin(), $1.code.rend());
		if (rev_code[0] == '\n')
			rev_code = rev_code.substr(1);
		auto newline_index = rev_code.find('\n');
		auto last_line = std::string(rev_code.begin(), rev_code.begin() + newline_index);
    	reverse(last_line.begin(), last_line.end());
		auto prefix = std::string("  ret i32");
		if (last_line.substr(0, prefix.length()) != prefix) {
        	// Add implicit return
			$1.code += "  ret i32 0\n";
    	}
	}

	std::cout << header << $1.code << footer << "\n";
};

statement_list: statement_list statement {
	$$.code = $1.code + $2.code;
	$$.addr = nullptr;
	$$.type = Type::Unknown;

} | %empty {
	$$.code = "";
	$$.addr = nullptr;
	$$.type = Type::Unknown;

};

statement: expression ';' {
	$$.code = $1.code;
	$$.addr = nullptr;
	$$.type = Type::Void;

} | '{' { symtab.push(); }  statement_list '}' {
	$$.code = $3.code;
	$$.type = $3.type;
	$$.addr = $3.addr;
	symtab.pop();

} | type IDENTIFIER '=' expression ';' {
	$$.code = "";
	$$.type = Type::Unknown;
	$$.addr = nullptr;

	if ($4.type == Type::Unknown) {
		// Expression is invalid
		yyerror("ERROR: CANNOT ASSIGN A VALUE OF TYPE 'UNKNOWN' TO VARIABLE '" + $2.code + "'");
	} else if (symtab.get($2.code)) {
		// Symbol already exists, cannot allocate two of the same variable	
		yyerror("ERROR: SYMBOL '" + $2.code + "' ALREADY EXISTS IN SYMBOL TABLE");
	} else {
		// Append expression code
		$$.code = $4.code;

		// Add symbol to table and allocate on stack
		auto llvm_type = get_llvm_type($1.type);
		symtab.put($2.code, $1.type);
		auto var = symtab.make_variable($2.code);
		
		// Generate alloca instruction code
		$$.code += "  " + var->location()->name() + " = alloca " + llvm_type + "\n";

		auto casted = cast_to_lhs_type($1.type, $4.addr, $$);
		if (casted) {
			// Generate store instruction code
			$$.code += "  store " + llvm_type + " " + casted->name() + ", " + llvm_type + "* " + var->location()->name() + "\n";

			$$.type = Type::Void;
			$$.addr = var->location();
		}
	}

} | type IDENTIFIER ';' {
	if (symtab.get($2.code)) {
		// Symbol already exists, cannot allocate two of the same variable
		$$.code = "";
		$$.type = Type::Unknown;
		$$.addr = nullptr;
		yyerror("ERROR: SYMBOL '" + $2.code + "' ALREADY EXISTS IN SYMBOL TABLE");
	} else {
		// Add symbol to table and allocate on stack
		auto llvm_type = get_llvm_type($1.type);
		symtab.put($2.code, $1.type);
		auto var = symtab.make_variable($2.code);
		$$.code = "  " + var->location()->name() + " = alloca " + llvm_type + "\n";
		$$.type = Type::Void;
		$$.addr = var->location();
	}

} | RETURN expression ';' {
	$$.code = $2.code;
	$$.type = Type::Unknown;
	$$.addr = nullptr;

	auto casted = cast_to_lhs_type(Type::Int, $2.addr, $$);
	if (casted) {
		auto llvm_type = get_llvm_type(Type::Int);
		$$.code += "  ret " + llvm_type + " " + casted->name() + "\n";
		$$.type = Type::Void;
	}

} | error ';' { // error is a special token defined by bison
	$$.code = "";
	$$.addr = nullptr;
	$$.type = Type::Void;
	yyerrok;
};

type: INT {
	$$.code = "";
	$$.addr = nullptr;
	$$.type = Type::Int;

} | FLOAT {
	$$.code = "";
	$$.addr = nullptr;
	$$.type = Type::Float;

} | CHAR {
	$$.code = "";
	$$.addr = nullptr;
	$$.type = Type::Char;

};

expression: expression '+' expression {
	$$.code = $1.code + $3.code;
	$$.type = Type::Unknown;
	$$.addr = nullptr;

	// These are modified by cast_for_binop, so they may point to different memory later on
	Address* lhs = $1.addr; 
	Address* rhs = $3.addr;

	if (cast_for_binop(lhs, rhs, $$)) {
		// lhs and rhs should have the same type, so just choose one
		auto temp = symtab.make_temp(lhs->type());
		auto llvm_type = get_llvm_type(lhs->type());

		if (lhs->type() == Type::Float) {
			$$.code += "  " + temp->name() + " = fadd " + llvm_type + " " + lhs->name() + ", " + rhs->name() + "\n";
		} else {
			$$.code += "  " + temp->name() + " = add " + llvm_type + " " + lhs->name() + ", " + rhs->name() + "\n";
		}

		$$.type = lhs->type();
		$$.addr = temp;
	}

} | expression '-' expression {
	$$.code = $1.code + $3.code;
	$$.type = Type::Unknown;
	$$.addr = nullptr;

	// These are modified by cast_for_binop, so they may point to different memory later on
	Address* lhs = $1.addr; 
	Address* rhs = $3.addr;

	if (cast_for_binop(lhs, rhs, $$)) {
		// lhs and rhs should have the same type, so just choose one
		auto temp = symtab.make_temp(lhs->type());
		auto llvm_type = get_llvm_type(lhs->type());

		if (lhs->type() == Type::Float) {
			$$.code += "  " + temp->name() + " = fsub " + llvm_type + " " + lhs->name() + ", " + rhs->name() + "\n";
		} else {
			$$.code += "  " + temp->name() + " = sub " + llvm_type + " " + lhs->name() + ", " + rhs->name() + "\n";
		}

		$$.type = lhs->type();
		$$.addr = temp;
	}

} | expression '*' expression {
	$$.code = $1.code + $3.code;
	$$.type = Type::Unknown;
	$$.addr = nullptr;

	// These are modified by cast_for_binop, so they may point to different memory later on
	Address* lhs = $1.addr; 
	Address* rhs = $3.addr;

	if (cast_for_binop(lhs, rhs, $$)) {
		// lhs and rhs should have the same type, so just choose one
		auto temp = symtab.make_temp(lhs->type());
		auto llvm_type = get_llvm_type(lhs->type());

		if (lhs->type() == Type::Float) {
			$$.code += "  " + temp->name() + " = fmul " + llvm_type + " " + lhs->name() + ", " + rhs->name() + "\n";
		} else {
			$$.code += "  " + temp->name() + " = mul " + llvm_type + " " + lhs->name() + ", " + rhs->name() + "\n";
		}

		$$.type = lhs->type();
		$$.addr = temp;
	}

} | expression '/' expression {
	$$.code = $1.code + $3.code;
	$$.type = Type::Unknown;
	$$.addr = nullptr;

	// These are modified by cast_for_binop, so they may point to different memory later on
	Address* lhs = $1.addr; 
	Address* rhs = $3.addr;

	if (cast_for_binop(lhs, rhs, $$)) {
		// lhs and rhs should have the same type, so just choose one
		auto temp = symtab.make_temp(lhs->type());
		auto llvm_type = get_llvm_type(lhs->type());

		if (lhs->type() == Type::Float) {
			$$.code += "  " + temp->name() + " = fdiv " + llvm_type + " " + lhs->name() + ", " + rhs->name() + "\n";
		} else {
			$$.code += "  " + temp->name() + " = sdiv " + llvm_type + " " + lhs->name() + ", " + rhs->name() + "\n";
		}

		$$.type = lhs->type();
		$$.addr = temp;
	}

} | expression '%' expression {
	$$.code = $1.code + $3.code;
	$$.type = Type::Unknown;
	$$.addr = nullptr;

	// These are modified by cast_for_binop, so they may point to different memory later on
	Address* lhs = $1.addr; 
	Address* rhs = $3.addr;

	if ($1.type == Type::Float || $3.type == Type::Float) {
		$$.code = "";
		$$.type = Type::Unknown;
		$$.addr = nullptr;
		yyerror("ERROR: MODULUS OPERATOR CANNOT BE USED ON OPERAND OF TYPE 'FLOAT'");
	} else if (cast_for_binop(lhs, rhs, $$)) {
		// lhs and rhs should have the same type, so just choose one
		auto temp = symtab.make_temp(lhs->type());
		auto llvm_type = get_llvm_type(lhs->type());

		$$.code += "  " + temp->name() + " = srem " + llvm_type + " " + lhs->name() + ", " + rhs->name() + "\n";

		$$.type = lhs->type();
		$$.addr = temp;
	}

} | IDENTIFIER '=' expression {
	$$.code = "";
	$$.type = Type::Unknown;
	$$.addr = nullptr;

	auto lhs = symtab.make_variable($1.code);
	if (!lhs) {
		// Variable wasn't declared yet
		yyerror("ERROR: VARIABLE '" + $1.code + "' WAS USED BEFORE IT WAS DECLARED");
	} else {
		auto llvm_type = get_llvm_type(lhs->type());
		$$.code += $3.code;

		// Cast variable to lhs type
		auto casted = cast_to_lhs_type(lhs->type(), $3.addr, $$);
		if (casted) {
			// Generate store instruction code
			$$.code += "  store " + llvm_type + " " + casted->name() + ", " + llvm_type + "* " + lhs->location()->name() + "\n";

			$$.type = casted->type();
			$$.addr = casted;	
		}
	}

} | '-' expression %prec UMINUS {
	$$.code = $2.code;

	auto temp = symtab.make_temp($2.type);
	auto llvm_type = get_llvm_type($2.type);

	if ($2.type == Type::Float) {
		$$.code += "  " + temp->name() + " = fneg " + llvm_type + " " + $2.addr->name() + "\n";
	} else {
		$$.code += "  " + temp->name() + " = sub " + llvm_type + " 0" + ", " + $2.addr->name() + "\n";
	}

	$$.type = $2.type;
	$$.addr = temp;

} | '(' expression ')' {
	// Forward the value of the expression
	$$.code = $2.code;
	$$.addr = $2.addr;
	$$.type = $2.type;

} | INT_LITERAL {
	auto addr = symtab.make_int_const(std::stoi($1.code));
	$$.code = "";
	$$.type = addr->type();
	$$.addr = addr;

} | FLOAT_LITERAL {
	auto addr = symtab.make_float_const(std::stof($1.code));
	$$.code = "";
	$$.type = addr->type();
	$$.addr = addr;

} | CHAR_LITERAL {
	auto addr = symtab.make_char_const($1.code[1]);
	$$.code = "";
	$$.type = addr->type();
	$$.addr = addr;

} | IDENTIFIER {
	$$.code = "";
	$$.type = Type::Unknown;
	$$.addr = nullptr;

	auto var = symtab.make_variable($1.code);
	if (!var) {
		// Variable wasn't declared yet
		yyerror("ERROR: VARIABLE '" + $1.code + "' WAS USED BEFORE IT WAS DECLARED");
	} else {
		auto temp = symtab.make_temp(var->type());
		auto llvm_type = get_llvm_type(var->type());

		// Generate load instruction code	
		$$.code = "  " + temp->name() + " = load " + llvm_type + ", " + llvm_type + "* " + var->location()->name() + "\n"; 

		$$.type = var->type();
		$$.addr = temp;	
	}
};


%%

int main()
{
	int result = yyparse();
	yylex_destroy();
	return result;
}
