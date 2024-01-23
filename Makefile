BINARIES = c2ll

# -Wclass-memaccess reports problems with using C++ types in YYSTYPE.
# Disable those (not the best solution).
CXXFLAGS = -std=c++17 -Wall -Wno-class-memaccess
FLEXFLAGS = 
BISONFLAGS = 

all: $(BINARIES)

.PRECIOUS: %.cc %.hh

clean:
	-rm $(BINARIES) parser.cc parser.hh lexer.cc parser.o lexer.o

c2ll: parser.o lexer.o
	$(CXX) $(CXXFLAGS) -o $@ $^ -lfl

# Make sure we build parser.hh before compiling the lexer
lexer.o: lexer.cc parser.hh globals.h types.h

# parser.hh comes from building parser.cc
parser.hh: parser.cc

# Rebuild parser if globals.h or types.h changes.
parser.o: parser.cc globals.h types.h

%.o: %.cc
	$(CXX) $(CXXFLAGS) -c $<

%.cc: %.l
	flex $(FLEXFLAGS) -o $@ $<

# -d to also create a header file (.hh/.h instead of .cc/.c)
%.cc: %.y
	bison $(BISONFLAGS) -d -o $@ $<
