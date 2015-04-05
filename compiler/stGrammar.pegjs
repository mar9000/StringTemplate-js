/*
 * stGrammar.pegjs
 * This is the grammar for StringTemplate including group files, template files, and raw templates
 */
/*
 [The "BSD licence"]
 Copyright (c) 2015, John Snyders
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 1. Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
 3. The name of the author may not be used to endorse or promote products
    derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

{
    var VALID_DELIMITERS =  "#$%^&*<>";

    var delimiterStartChar = "<",
        delimiterStopChar = ">",
        curGroup = options.group,
        curDict = null,
        outside = true,
        verbose = false,
        formalArgsHasOptional = false;

    var logger = function(message) {
        console.log(message);
    }

    function verboseLog(message) {
        if (verbose) {
            logger(message);
        }
    }

    function makeList(first, rest) {
        var list;
        if (first && rest) {
            list = [first].concat(rest);
        } else if (first) {
            list = [first];
        } else if (rest) {
            list = rest;
        } else {
            list = [];
        }
        return list;
    }

    function parseTemplate(template) {
        var ignoreNewLines = false, // xxx make use of this
            lineOffset = line() - 1;

        if (template.ignoreNewLines) {
            ignoreNewLines = true;
            template = template.string;
        }

        outside = true; // just in case, make sure always start parsing a template on the outside
        try {
            return parse(template, {
                startRule: "templateAndEOF",
                group: curGroup,
                verbose: verbose,
                delimiterStartChar: delimiterStartChar,
                delimiterStopChar: delimiterStopChar
            });
        } catch(ex) {
            if (ex instanceof SyntaxError) {
                ex.line += lineOffset;
            }
            throw ex;
        }
    }

    delimiterStartChar = options.delimiterStartChar || "<";
    delimiterStopChar = options.delimiterStopChar || ">";
    verbose = options.verbose || false;
    if (options.logger) {
        logger = options.logger;
    }

    verboseLog("Initial delimiters: " + delimiterStartChar + ", " + delimiterStopChar);

}

/*
 * GROUP
 */

/*
 * ENTRY POINT: group
 * This entry point is for a .stg file.
 *
 * There should be at least one definition but not enforced
 */
group
    = __ delimiters? __ import* __ def* __ EOF {
            return curGroup;
        }

import
    = __ "import" __ file:STRING __ {
            curGroup.addImports(file.value);
            return null;
        }

delimiters
    = "delimiters" __ s:STRING __ "," __ e:STRING {
            var start = s.value,
                stop = e.value;
            if (start.length !== 1 || stop.length !== 1) {
                error("Delimiter value must be exactly one character");
            }
            if (VALID_DELIMITERS.indexOf(start) < 0 || VALID_DELIMITERS.indexOf(stop) < 0) {
                error("Invalid delimiter character");
            }
            delimiterStartChar=s.value.charAt(0);
            delimiterStopChar=e.value.charAt(0);
            verboseLog("Delimiters: " + delimiterStartChar + ", " + delimiterStopChar);
            return null;
        }

def
    = __ d:dictDef __ { return d }
    / __ d:templateDef __ { return d; }

/*
 * ENTRY POINT: templateDef
 * This entry point is for a non-raw .st file
 * xxx also used internally as part of a group definition
 *   when used for a .st file is region or alias really allowed? Also only in that case need to enforce name and filename match
 *   also when used as the .st entry point need to allow whitespace prolog and epilog
 */
templateDef
    = def:( "@" enclosing:ID "." n:ID "(" __ ")" {
                    return { type: "xxx" }; // todo region stuff
                }
            /	n:ID "(" __ args:formalArgs __ ")" {
                    return {
                        name: n.value,
                        args: args
                    };
                }
        )
        __ "::=" __
        template:(
            s:STRING { return s.value }
            / s:BIGSTRING { return s.value }
            / s:BIGSTRING_NO_NL { return s.value }
            / { error("missing template"); }
        ) {
            verboseLog("Template definition: " + def.name);
            def.template = parseTemplate(template).value;
            curGroup.addTemplate(def);
            return null;
        }
    / alias:ID __ '::=' __ target:ID  {
            verboseLog("Template alias: " + name.value + " > " + target.value);
            curGroup.addTemplateAlias(alias.value, target.value);
            return null;
        }

formalArgs
    = &{ formalArgsHasOptional = false; return true; } first:formalArg rest:( __ ',' __ e:formalArg { return e; } )* {
            return makeList(first, rest);
        }
    / { return []; }

formalArg
    = name:ID defaultValue:( __ '=' __
            v:( s:STRING {return s.value;}
                /*xxx|ANONYMOUS_TEMPLATE*/
                / TRUE { return true; }
                / FALSE { return false; }
                / "[" __ "]" { return []; } ) {
                        formalArgsHasOptional = true;
                        return v;
                    }
        )? {
                var ret;

                if (formalArgsHasOptional && defaultValue === null) {
                    error("Required argument after optional not allowed.");
                }
                ret = {
                    type: "FORMAL_ARG",
                    name: name.value,
                };
                if (defaultValue) {
                    ret.defaultValue = defaultValue;
                }
                return ret;
            }

dictDef
	= (__ id:ID __ '::=' { curDict = { name: id.value, map: {}, default: null }; }) dict {
            verboseLog("Dictionary definition: " + curDict.name);
            curGroup.addDictionary(curDict);
            curDict = null;
            return null;
        }

dict
	= __ "[" __ dictPairs "]" __

dictPairs
    = __ keyValuePair (__ ',' __ keyValuePair)* (__ ',' __ defaultValuePair)?
    / __ def:defaultValuePair

defaultValuePair
    = "default" __ ":" __ v:keyValue __ { curDict.default = v; }

keyValuePair
    = k:STRING __ ':' __ v:keyValue __ { curDict.map[k.value] = v; }

keyValue
    = v:BIGSTRING           { return v.value; }
    / v:BIGSTRING_NO_NL     { return v.value; }
    / v:STRING              { return v.value; }
    / v:anonymousTemplate	{ return v; }
    / TRUE                  { return true; }
    / FALSE                 { return false;}
    / "key"                 { return 0; } // xxx need an out of band value for this
    / '[' __ ']'            { return []; }


// xxx this is very broken
anonymousTemplate
    = "{" (!"}" .)* "}" { return {
                type: "ANON_TEMPLATE",
                value: text() // xxx
            };
        }

/*
 * RAW TEMPLATE
 */

/*
 * ENTRY POINT: templateAndEOF
 * This entry point is used internally to parse the body of a template definition
 */
templateAndEOF
    = t:template EOF {
            return t;
        }

/*
 * ENTRY POINT: templateRaw
 * This entry point is for raw .st files
 */
templateRaw
    = t:template EOF {
            curGroup.addTemplate({
                name: curGroup.fileName,
                args: null, // xxx is this OK?
                templatet: t.value
            });
            return curGroup;
        }

template
    = e:(!(INDENT? START_CHAR "elseif" / INDENT? START_CHAR "else" / INDENT? START_CHAR "endif" ) i:element { return i; })* { return {
                type: "TEMPLATE",
                value: e || null // xxx should this be null or text token with empty string value
            }
        }

element
    = &{return column() === 1;} INDENT? ST_COMMENT NEWLINE { return null; }
    / INDENT se:singleElement {
            return {
                type: "INDENTED_EXPR",
                value: se
            };
        }
    / &{ outside=true; return true } se:singleElement {
            return se;
        }
    / &{ outside=true; return true } ce:compoundElement {
            return ce;
        }

singleElement
    = TEXT
    / NEWLINE
    / ST_COMMENT { return null; }
    / exprTag

compoundElement
    = ifstat
    / region

exprTag
	= START e:expr opts:( ';' o:exprOptions { return o; } )? STOP {
	        var ret = {
	            type: "EXPR",
	            expr: e
	        };
	        if (opts) {
	            ret.options = opts;
	        }
	        return ret;
        }

// xxx todo region stuff
region
    = INDENT? START '@' ID STOP template INDENT? START '@end' STOP

/*xxx        // kill \n for <@end> on line by itself if multi-line embedded region
        ({$region.start.getLine()!=input.LT(1).getLine()}?=> NEWLINE)?
        -> {indent!=null}?
           ^(INDENTED_EXPR $i ^(REGION[$x] ID template?))
        ->                    ^(REGION[$x] ID template?) */

  // ignore final INDENT before } as it's not part of outer indent
subtemplate
    = '{' ( args:formalArgsNoDefault '|' )? template INDENT? '}' {
            return {
                type: "SUBTEMPLATE",
                args: args.args,
                template: template
            };
        }

formalArgsNoDefault
    = first:ID ( __ ',' __ rest:ID)* {
            return {
                type: "ARGS",
                args: makeList(first, rest)
            }
        }

ifstat
	= i:INDENT? START "if" __ "(" __ c1:conditional __ ")" STOP /*xxx{if (input.LA(1)!=NEWLINE) indent=$i;} */
        t1:template
        ( !(INDENT? START_CHAR "else" STOP_CHAR) INDENT? START "elseif" __ "(" __ c2:conditional __ ")" STOP t2:template )* // xxx how to gather all the t2s?
        ( INDENT? START "else" STOP t3:template )?
        INDENT? START "endif" STOP {
                return {
                    type: "IF",
                    condition: c1,
                    then: t1
                    // xxx what else
                };
            }
/*xxx		// kill \n for <endif> on line by itself if multi-line IF
		({$ifstat.start.getLine()!=input.LT(1).getLine()}?=> NEWLINE)?
		-> {indent!=null}?
		   ^(INDENTED_EXPR $i ^('if' $c1 $t1? ^('elseif' $c2 $t2)* ^('else' $t3?)?))
		->                    ^('if' $c1 $t1? ^('elseif' $c2 $t2)* ^('else' $t3?)?) */

conditional
    = andConditional ( __ "||" __ andConditional )*

andConditional
    = notConditional ( __ "&&" __ notConditional )*

notConditional
    = "!" __ notConditional
    / memberExpr

exprOptions
    = first:option rest:( __ ',' __ o:option { return o; } )* {
            return makeList(first, rest);
        }

/*
@init {
	String id = input.LT(1).getText();
	String defVal = Compiler.defaultOptionValues.get(id);
	boolean validOption = Compiler.supportedOptions.get(id)!=null;
...
        if ( !validOption ) {
            errMgr.compileTimeError(ErrorType.NO_SUCH_OPTION, templateToken, $ID, $ID.text);
        }

}
*/
option
    = name:ID val:( __ "=" __ e:exprNoComma { return e; } )? {
            var optionName = name.value,
                value;
            if (!curGroup.isValidOption(optionName)) {
                error("No such option " + optionName);
            }
            value = val || curGroup.defaultOptionValue(optionName);
            if (!value) {
                error("Value required for option " + optionName);
            }
            return {
                type: "OPTION",
                name: optionName,
                value: value
            };
        }

exprNoComma
    = me:memberExpr ref:( ':' tr:mapTemplateRef { return tr; } )? {
            if (ref) {
                return {
                    type: "MAP",
                    expr: me,
                    template: ref
                };
            } else {
                return me;
            }
        }

expr "expression"
    = mapExpr

/*xxx
// xxx comment from ST
// more complicated than necessary to avoid backtracking, which ruins
// error handling
mapExpr
    = first:memberExpr ( ("," rest:memberExpr)+ ":" mapTemplateRef {
                    return {
                        type: "ZIP",
                        value: "xxx" // ^(ELEMENTS memberExpr+) mapTemplateRef
                    }
            })
        / { return first; }
        )
        (	 /// xxx {if ($x!=null) $x.clear();} // don't keep queueing x; new list for each iteration
            ":" x:mapTemplateRef ({$c==null}?=> ',' xs:mapTemplateRef )* {
                    return {
                        type
                    };
                }
//xxx                                                -> ^(MAP[$col] $mapExpr $x+)
        )*
*/

/*
 *
 */
mapExpr
    = m1:memberExpr zip:( ( __ "," __ memberExpr )+ __ ":" __ mapTemplateRef )?
        map:( ":" __ mapTemplateRef ( __ "," __ mapTemplateRef )*  )* {
                if (zip) {
                    return {
                        type: "ZIP"
                        //xxx
                    };
                } else if (map.length > 0) {
                    return {
                        type: "MAP"
                        //xxx
                    };
                } else {
                    return m1;
                }
            }

/**
expr:template(args)  apply template to expr
expr:{arg | ...}     apply subtemplate to expr
expr:(e)(args)       convert e to a string template name and apply to expr
*/
//xxx
mapTemplateRef
    = ID '(' args ')' //xxx							-> ^(INCLUDE ID args?)
    / subtemplate
    / '(' mapExpr ')' '(' argExprList? ')' // xxx -> ^(INCLUDE_IND mapExpr argExprList?)

/*
 * <attribute.property> // value of property of object attribute
 * <attribute.property.property> // any number of levels of property references
 * <attribute.(expr)> // indirect property reference. value of expr is name of property of object attribute
 * <attribute.(expr).(expr)> // any number of levels allowed
 * <attribute.property.(expr). // can mix direct and indirect property references
 * xxx it seems strange that member references are allowed on anything other than an attribute
 *  what does true.myProp mean?
 *  or template(arg1, arg2).prop2
 */
memberExpr
    = e:includeExpr
        props:( '.' prop:ID {
                return {
                    type: "PROP",
                    property: prop.value
                }
            }
        / '.' '(' e:mapExpr ')' {
                return {
                    type: "PROP_IND",
                    property: e
                }
            }
        )* {
                if (props.length > 0) {
                    return {
                        type: "MEMBER_EXPR",
                        object: e,
                        properties: props
                    }
                } else {
                    return e;
                }
            }
/*
 * <func(expr)> // func is one of the built in functions: first, length, strlen, last, rest, reverse, trunc, strip, trim
 * xxx super?
 * <template(exp1, exp2...)>
 * <template(formalArg1=exp1, formalArg2=exp2...)>
 * xxx
 * Or primary
 */
includeExpr
    = i:ID &{ return curGroup.isFunction(i.value); } __ '(' __ e:expr? __ ')' {
            return {
                type: "FUNCTION",
                name: i.value,
                arg: e
            };
        }
    / "super." i:ID '(' a:args ')' { // xxx todo region stuff
            return {
                type: "INCLUDE_SUPER",
                name: i.value,
                args: a
            };
        }
    / i:ID '(' a:args ')' {
             return {
                 type: "INCLUDE",
                 name: i.value,
                 args: a
             };
         }
// xxx todo region stuff
//xxx	|	'@' 'super' '.' ID '(' rp=')'			-> ^(INCLUDE_SUPER_REGION ID)
//xxx	|	'@' ID '(' rp=')'						-> ^(INCLUDE_REGION ID)
    / primary

/*
 * true
 * false
 * <attriburte>
 * "string"
 * xxx
 */
primary
    = TRUE { return true; }
    / FALSE { return false; }
    / i:ID { return {
                type: "ATTRIBUTE",
                name: i.value
            };
        }
    / s:STRING { return s.value }
    / subtemplate
    / list
//xxx    |	{$conditional.size()>0}?=>  '('! conditional ')'!
//    |	{$conditional.size()==0}?=> lp='(' expr ')'
//        (	'(' argExprList? ')'		        -> ^(INCLUDE_IND[$lp] expr argExprList?)
//        |										-> ^(TO_STR[$lp] expr)
//        )

args
    = argExprList?
	/ first:namedArg rest:( __ ',' __ a:namedArg { return a; } )* passThrough:( __ ',' __ pt:'...' { return true; })? {
	        var ret = {
                type: "ARGS",
                value: makeList(first, rest)
	        };
	        if (passThrough) {
	            ret.passThrough = true;
	        }
	        return ret;
	    }
    / '...' {
            return {
                type: "ARGS",
                value: [],
                passThrough: true
            };
        }

argExprList
    = first:arg rest:( __ ',' __ a:arg { return a; } )* {
            return {
                type: "ARGS",
                value: makeList(first, rest)
            };
        }

arg
    = exprNoComma

namedArg
    = i:ID __ '=' __ v:arg {
            return {
                type: "ARG",
                name: i,
                value: v
            };
        }

list
    = "[" __ first:listElement? rest:( __ "," __ i:listElement { return i; } )* __ "]" {
            return {
                type: "LIST",
                value: makeList(first, rest)
            };
        }

listElement
    = exprNoComma
    / { return null; }

/*
 * lexical terminals
 */

WS_CHAR
    = " "
    / "\t"

EOL "end of line"
    = "\n"
    / "\r\n"
    / "\r"

COMMENT
    = "/*" (!"*/" .)* "*/"

LINE_COMMENT
    = "//" (!EOL .)*

__ "white space"
    = (WS_CHAR / EOL / COMMENT / LINE_COMMENT )*

/*
 * xxx when defining a template / is not allowed but in a template when referencing a template it is.
 */
ID	"identifier"
	= !(RESERVED) [a-zA-Z_/] [a-zA-Z_/0-9]* {
	        return {
	            type: "ID",
	            value: text()
	        };
	    }

/*
 * According to the doc these are all "reserved words" but the Java ST parser seems to allow some in some contexts
 * true, false, import, default, key, group, implements, first, last, rest, trunc, strip, trim, length, strlen, reverse, if, else, elseif, endif, delimiters
 */
RESERVED
    = "true"
    / "false"
    / "if"
    / "else"
    / "elseif"
    / "endif"
    / "super"
    / "import"
    / "default"
    / "key"
    / "group"
    / "delimiters"
// This is old v3 keyword so allow it
//    / "implements"
// The functions need to be included as identifiers because they are tested to be functions later

TRUE
    = "true" { return { type: "TRUE" }; }

FALSE
    = "false" { return { type: "FALSE" }; }

STRING "string"
    = '"' chars:STRING_CHAR* '"' {
            return { type: "STRING", value: chars.join("") };
        }

STRING_CHAR
    = !('"' / "\\" / "\r" / "\n") . { return text(); }
    / "\\" sequence:ESCAPE_CHAR { return sequence; }
    / EOL { error("Unterminated string"); }

ESCAPE_CHAR
    = "n" { return "\n"; }
    / "r" { return "\r"; }
    / "t" { return "\t"; }
    / . { return text(); }

/** Match <<...>> but also allow <<..<x>>> so we can have tag on end.
    Escapes: >\> means >> inside of <<...>>.
    Escapes: \>> means >> inside of <<...>> unless at end like <<...\>>>>.
    In that case, use <%..>>%> instead.
 */
BIGSTRING "big string"
    = "<<" chars:BIGSTRING_CHAR* ">>" {
            return {
                type: "BIGSTRING",
                value: chars.join("") // xxx escapes
            };
        }

BIGSTRING_CHAR
    = !(">>" / "\\>>" / ">\\>") . { return text(); }
    / "\\>>" { return ">>"; }
    / ">\\>" { return ">>"; }
//xxx    / EOF { error("Unterminated big string"); }

// same as BIGSTRING but means ignore newlines later
BIGSTRING_NO_NL "big string"
    = "<%" (!"%>" .)* "%>" {
            var txt = text();
            return {
                type: "BIGSTRING_NO_NL", // xxx consider "BIGSTRING"
                value: {
                    ignoreNewLines: true,
                    // %\> is the escape to avoid end of string
                    string: txt.substring(2, txt.length - 2).replace(/\%\\>/g, "%>")
                }
            };
        }

EOF "end of file"
    = !.

/*
 * OUTSIDE
 */

INDENT
    = &{return outside && column() === 1;} WS_CHAR+ {
            return { type: "INDENT" };
        }

START
    = &{return outside;} !( START_CHAR "!") START_CHAR {
            outside = false;
            return { type: "START" };
        }
/*
 * Character that starts an expression. This is configurable. Typically < or $
 */
START_CHAR
    = &{ return (input.charAt(peg$currPos) === delimiterStartChar) } .

/*
 * <! comment !>
 */
ST_COMMENT
    = &{return outside;} START_CHAR "!" (!("!" STOP_CHAR) .)* "!" STOP_CHAR {
            return { type: "ST_COMMENT" };
        }
/*
 * Any text outside an expression except for new lines
 * text returned as is except for escapes
 */
TEXT
    = &{return outside;} chars:TEXT_CHAR+ {
            return {
                type: "TEXT",
                value: chars.join("") // can't use text() unless it fixes up escapes
            };
        }

// xxx something about RCURLY needed
TEXT_CHAR
    = !(EOL / START_CHAR / "\\" START_CHAR / "\\\\" / ESCAPE) . {
            return text();
        }
    / "\\" START_CHAR { return delimiterStartChar; }
    / START_CHAR !("\\\\") e:ESCAPE* STOP_CHAR { return e.join(""); }
    / START_CHAR "\\\\" STOP_CHAR WS_CHAR* EOL ch:.? { return ch; }


/*
 * \< or \> -> < or >
 * <\ >, <\n>, <\t>, <\r> -> space, line feed, tab, carriage return  - can have multiple
 * <\uXXXX> -> Unicode character - can have multiple
 * <\\> ([ \t])*(\r|\r\n|\n). -> .  // ignores new line
 */
ESCAPE
    = "\\" ch:( "u" HEX_DIGIT HEX_DIGIT HEX_DIGIT HEX_DIGIT { return String.fromCharCode(parseInt(text().substr(1), 16)); }
        / "n" { return "\n"; }
        / "r" { return "\r"; }
        / "t" { return "\t"; }
        / " " { return " "; }
        / . {
                error("Invalid escape character '" + text() + "'");
            }
        ) { return ch; }

HEX_DIGIT
    = [0-9a-fA-F]

NEWLINE
    = &{return outside;} EOL {
            return {
                type: "NEWLINE",
                value: text()
            }
        }

/*
 * INSIDE
 */
STOP "stop delimiter"
    = !{return outside;} STOP_CHAR {
            outside = true;
            return { type: "STOP" };
        }
/*
 * Character that stops an expression. This is configurable. Typically > or $
 */
STOP_CHAR
    = &{ return (input.charAt(peg$currPos) === delimiterStopChar) } .