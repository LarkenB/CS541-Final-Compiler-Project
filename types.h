#ifndef TYPES_H_INCLUDED
#define TYPES_H_INCLUDED

#include <string>
#include <list>
#include <unordered_map>
#include <vector>
#include <cstring> // memcpy
#include <cstdio>  // sprintf
#include <cstdint> // uint64_t

namespace clukcs {

// Get the number of a new temporary address.
inline int get_new_temp() {
	static int next_temp = 1;
	return next_temp++;
}

// The type of an expression. This does not handle pointers, arrays,
// and records (structs): Those would require more complicated storage.
//
// Refer to these as cluks::Type::Int, etc.
enum class Type {
	Unknown,  // Type has not been set yet.
	Void,     // The type of statements.
	Int,
	Float,
	Char
};


///////////////////////////////////////////////////////


// Abstract base class for an address (in the sense of three-address code).
class Address {
public:
	// Return a string representation of the address.
	virtual std::string name() const = 0;
	// Return the type of the address's value.
	virtual Type type() const = 0;

	// Classes with virtual methods should have virtual destructors.
	virtual ~Address() = default;
};

// A symbol table entry.
struct Symbol {
	std::string name;
	Address *location; // Temporary
	Type type;
};

// An Address pointing to a variable in the symbol table.
class Variable : public Address {
public:
	// sym should already exist in the symbol table: Specifically, it
	// must be a non-null value returned by symbol_table::get() *after*
	// the most recent call to symbol_table::pop().
	Variable(Symbol *sym)
		: sym{sym}
	{ }

	std::string name() const override { return sym->name; }
	Address *location() const { return sym->location; }
	Type type() const override { return sym->type; }
private:
	// The symbol table owns this symbol, so we don't have to free it.
	Symbol *sym;
};

// An address representing the intermediate result of an expression.
class Temporary : public Address {
public:
	Temporary(Type var_type)
		: num{get_new_temp()}, var_type{var_type}
	{ }
	std::string name() const override { return "%t" + std::to_string(num); }
	Type type() const override { return var_type; }
private:
	int num; // Unique number for this Temporary
	Type var_type;
};

// An address representing an integer constant.
class IntValue : public Address {
public:
	IntValue(int value) : value(value) { }
	std::string name() const override { return std::to_string(value); }
	Type type() const override { return Type::Int; }
private:
	int value;
};

// An address representing a floating-point constant.
class FloatValue : public Address {
public:
	FloatValue(float value) : value(value) { }
	std::string name() const override {
		// Convert to hexadecimal by reinterpreting the bits as
		// a 64-bit unsigned integer.
		uint64_t as_int;
		double dval = value;
		std::memcpy(&as_int, &dval, sizeof(as_int));
		// Two characters per byte, plus "0x", plus null terminator.
		char buf[2 * sizeof(as_int) + 3];
		std::sprintf(buf, "0x%lX", as_int);
		return std::string(buf);
	}
	Type type() const override { return Type::Float; }
private:
	float value;
};

// An address representing a character constant.
class CharValue : public Address {
public:
	CharValue(char value) : value(value) { }
	std::string name() const override { return std::to_string(int(value)); }
	Type type() const override { return Type::Char; }
private:
	char value;
};




// A table mapping names to symbols: 
class symbol_table {
public:
	// Create a symbol table with just one scope.
	symbol_table() { push(); }

	// Free all temporaries and constants we have created.  Symbols
	// themselves are handled by the destructor for this->scopes.
	~symbol_table() {
		for (auto ptr : addrs_to_free) {
			delete ptr;
		}
	}

	// Look up a symbol and return a pointer to its entry, or null if
	// there is no such symbol.
	Symbol *get(const std::string &name) {
		// From newest scope to oldest
		for (level &scope : scopes) {
			auto it = scope.find(name);
			if (it != scope.end()) {
				return &it->second;
			}
		}
		return nullptr;
	}

	// Insert a symbol and return a pointer to its entry.
	Symbol *put(const std::string &name, Type type) {
		Address *temp = make_temp(type);
		return &(scopes.front()[name] = Symbol{name, temp, type});
	}

	// Get a new variable Address from looking up a symbol (which should
	// already be in the symbol table). Returns null if there was no
	// symbol by that name.
	Variable *make_variable(const std::string &name) {
		if (Symbol *s = get(name)) {
			Variable *v = new Variable(s);
			addrs_to_free.push_back(v);
			return v;
		}
		// Nothing found
		return nullptr;
	}

	// Get a new temporary Address.
	Address *make_temp(Type type) {
		addrs_to_free.push_back(new Temporary(type));
		return addrs_to_free.back();
	}

	// Get a new constant value Address (one method for each basic type).
	Address *make_int_const(int value) {
		addrs_to_free.push_back(new IntValue(value));
		return addrs_to_free.back();
	}
	Address *make_float_const(float value) {
		addrs_to_free.push_back(new FloatValue(value));
		return addrs_to_free.back();
	}
	Address *make_char_const(char value) {
		addrs_to_free.push_back(new CharValue(value));
		return addrs_to_free.back();
	}

	// Add and remove symbol table levels.  Note that pop() makes invalid
	// all pointers that were previously returned from the newest scope.
	void push() { scopes.emplace_front(); }
	void pop()  { scopes.pop_front(); }
private:
	// A single "level" (scope) in the symbol table.
	typedef std::unordered_map<std::string, Symbol> level;

	// A list of levels, with the newest (deepest) first.
	std::list<level> scopes;

	// A vector of all the addresses that we have created; these aren't in the
	// symbol table proper, but are in this vector for memory-management purposes.
	std::vector<Address *> addrs_to_free;
};

///////////////////////////////////////////////////////

/* Semantic value for grammar symbols:
 *
 *   All three parts are used for expressions.
 *
 *   Only "code" is used for statements and statement lists.
 *
 *   Only "code" is used for identifiers and literals, where it holds the
 *   string representation of the identifier or literal.
 *
 *   Only type is used for types.
 */
struct parser_val {
	std::string code;
	Address *addr;
	Type type;
};

} // namespace clukcs

#endif // TYPES_H_INCLUDED
