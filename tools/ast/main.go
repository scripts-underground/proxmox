package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

type ScriptType string

const (
	TypeLXC   ScriptType = "lxc"
	TypeAddon ScriptType = "addon"
	TypePVE   ScriptType = "pve"
	TypeVM    ScriptType = "vm"
)

var collections = []ScriptType{TypeLXC, TypeAddon, TypePVE, TypeVM}
var hookNames = []string{
	"install_script", "update_script", "uninstall_script",
	"pre_build_script", "post_build_script", "post_install_script",
	"header_info",
}

// ---  Schema types (shared) ---

type LineRange struct {
	StartLine int `json:"start_line"`
	EndLine   int `json:"end_line"`
}

type Span struct {
	StartLine int    `json:"start_line"`
	StartCol  int    `json:"start_col"`
	EndLine   int    `json:"end_line"`
	EndCol    int    `json:"end_col"`
	Kind      string `json:"kind"`
}

type FunctionInfo struct {
	Name      string `json:"name"`
	StartLine int    `json:"start_line"`
	EndLine   int    `json:"end_line"`
	NameSpan  Span   `json:"name_span"`
}

type Assign struct {
	Name               string `json:"name"`
	Line               int    `json:"line"`
	StartCol           int    `json:"start_col"`
	EndCol             int    `json:"end_col"`
	ValueHasCmdSubst   bool   `json:"value_has_cmdsubst"`
	IsRepoBase         bool   `json:"is_repo_base"`
	InBootstrapZone    bool   `json:"in_bootstrap_zone"`
	ValueIsParamDefault bool  `json:"value_is_param_default"`
}

type OpInfo struct {
	Line int    `json:"line"`
	Col  int    `json:"col"`
	Kind string `json:"kind"`
}

// Marker describes one occurrence of the heredoc delimiter word
// (opening or closing). Text is the unquoted delimiter word (the
// identifier bash uses to match opening to closing).
type Marker struct {
	Line     int    `json:"line"`
	StartCol int    `json:"start_col"`
	EndCol   int    `json:"end_col"`
	Text     string `json:"text"`
}

type Heredoc struct {
	Op          OpInfo    `json:"op"`
	MarkerStart Marker    `json:"marker_start"`
	MarkerEnd   Marker    `json:"marker_end"`
	Body        LineRange `json:"body"`
	Expand      bool      `json:"expand"`
	StripTabs   bool      `json:"strip_tabs"`
}

type Flags struct {
	Docker bool `json:"docker"`
	Podman bool `json:"podman"`
	NPM    bool `json:"npm"`
	Yarn   bool `json:"yarn"`
	Pnpm   bool `json:"pnpm"`
	Pip    bool `json:"pip"`
	Cargo  bool `json:"cargo"`
	Go     bool `json:"go"`
	Git    bool `json:"git"`
	Sudo   bool `json:"sudo"`
	Eval   bool `json:"eval"`
}

type SystemdService struct {
	Name     string `json:"name"`
	Path     string `json:"path"`
	User     string `json:"user"`
	Required bool   `json:"required"`
}

type OpenRCService struct {
	Name     string `json:"name"`
	Path     string `json:"path"`
	User     string `json:"user"`
	Required bool   `json:"required"`
}

type ScriptUser struct {
	Name   string `json:"name"`
	Source string `json:"source"`
	Line   int    `json:"line,omitempty"`
}

type InteractivePrompt struct {
	Kind string `json:"kind"`
	Text string `json:"text"`
	Line int    `json:"line"`
}

// Token represents one parsable token from the bash AST.  Kinds are
// documented alongside the struct.  Op carries the literal text for
// operator / keyword / var-assign kinds.  Expand is set only for
// heredoc-delim tokens.
type Token struct {
	Kind      string `json:"kind"`
	Op        string `json:"op,omitempty"`
	StartLine int    `json:"start_line"`
	StartCol  int    `json:"start_col"`
	EndLine   int    `json:"end_line"`
	EndCol    int    `json:"end_col"`
	Expand    bool   `json:"expand,omitempty"`
}

// ASTOutput is the schema_version 2 format.  Tokens
// are new in v2.  Comments and Heredoc.CodeSpans / Heredoc.Delim /
// Heredoc.Closing have been removed (tokens cover that data).
type ASTOutput struct {
	SchemaVersion int    `json:"schema_version"`
	Slug          string `json:"slug"`
	Type          string `json:"type"`
	TotalLines    int    `json:"total_lines"`
	Source        string   `json:"source"`
	SourceLines   []string `json:"source_lines"`

	Functions        []FunctionInfo `json:"functions"`
	Assigns          []Assign       `json:"assigns"`
	GlobalRanges     []LineRange    `json:"global_ranges"`
	Heredocs         []Heredoc      `json:"heredocs"`
	DownloadSpans    []Span         `json:"download_spans"`
	PipedDownloadSpans []Span       `json:"piped_download_spans"`
	ExternalSpans    []Span         `json:"external_spans"`

	Tokens []Token `json:"tokens"`

	BootstrapLine int             `json:"bootstrap_line"`
	Hooks         map[string]bool `json:"hooks"`
	HookOrder     []string        `json:"hook_order"`
	Flags         Flags           `json:"flags"`
	HasDownload      bool `json:"has_download"`
	HasPipedDownload bool `json:"has_piped_download"`
	HasExternal      bool `json:"has_external"`
	HasEval          bool `json:"has_eval"`
	HasGlobal        bool `json:"has_global"`
	HasBootstrap     bool `json:"has_bootstrap"`

	SystemdServices     []SystemdService     `json:"systemd_services"`
	OpenRCServices      []OpenRCService      `json:"openrc_services"`
	ServiceManagers     []string             `json:"service_managers"`
	Users               []ScriptUser         `json:"users"`
	InteractivePrompts  []InteractivePrompt  `json:"interactive_prompts"`
}

var downloadCommands = map[string]bool{
	"curl": true,
	"wget": true,
}

var shellEvalCommands = map[string]bool{
	"bash":   true,
	"sh":     true,
	"eval":   true,
	"source": true,
	".":      true,
}

// utf16LenOfLine returns the length of a string in UTF-16 code units.
func utf16LenOfLine(s string) int {
	n := 0
	for _, r := range s {
		if r >= 0x10000 {
			n += 2
		} else {
			n++
		}
	}
	return n
}

// --- Walker state ------------------------------------------------------------

type frameType int

const (
	frameOther frameType = iota
	frameFuncDecl
	frameIfClause
	frameShellEval
)

type funcScope struct {
	name       string
	dependents map[string]bool
}

type walker struct {
	src       string
	funcs     []FunctionInfo
	assigns   []Assign
	globalRanges []LineRange
	heredocs  []Heredoc
	extSpans  []Span
	flags     Flags
	bootLine  int
	tokens              []Token
	scriptLines         []string
	frames              []frameType
	shellEvalDepth      int
	evalStack           []Span
	pushedEval          bool
	hasDownload         bool
	downloadSpans       []Span
	pipedDownloadSpans  []Span

	// Function-call detection state
	mainList     map[string]bool
	scopeStack   []funcScope
	dependentsOf map[string]map[string]bool

	// Heredoc output path tracking
	pendingOutputPath string
	heredocOutputs    map[int]string
}

func (w *walker) posLine(p syntax.Pos) int { return int(p.Line()) }
func (w *walker) posCol(p syntax.Pos) int  { return int(p.Col()) }

func (w *walker) insideFunc() bool {
	return len(w.scopeStack) > 0
}

func (w *walker) emitToken(t Token) {
	w.tokens = append(w.tokens, t)
}

// isFuncCall checks whether name is visible in the current scope chain.
func (w *walker) isFuncCall(name string) bool {
	// Check top-of-stack scope name (recursive self-call)
	if len(w.scopeStack) > 0 && w.scopeStack[len(w.scopeStack)-1].name == name {
		return true
	}
	// Check all scope dependents (innermost first)
	for i := len(w.scopeStack) - 1; i >= 0; i-- {
		if w.scopeStack[i].dependents[name] {
			return true
		}
	}
	// Check main list
	return w.mainList[name]
}

// addFuncCall adds name to the current function's dependents, or to
// mainList if we are at the top level.
func (w *walker) addFuncName(name string) {
	if w.insideFunc() {
		top := &w.scopeStack[len(w.scopeStack)-1]
		top.dependents[name] = true
	} else {
		w.mainList[name] = true
	}
}

// removeFuncName removes name wherever it lives in the visibility chain.
func (w *walker) removeFuncName(name string) {
	// Check main list first
	delete(w.mainList, name)
	// Remove from mainList's dependents too — they were conditional
	delete(w.dependentsOf, name)
	// Check current scope stack
	for i := range w.scopeStack {
		delete(w.scopeStack[i].dependents, name)
	}
}

// promoteFunc promotes one level: if the caller has pending dependents,
// move them into the current scope.
func (w *walker) promoteFunc(name string) {
	deps, ok := w.dependentsOf[name]
	if !ok || len(deps) == 0 {
		return
	}
	target := w.mainList
	if w.insideFunc() {
		top := &w.scopeStack[len(w.scopeStack)-1]
		// Promote into the scope where the function was called — for shallow
		// promotion, this means the caller's scope (which could be a scope
		// frame or mainList depending on where we found the function).
		// If the function was called from inside a function, promote into
		// that function's dependents.
		if len(w.scopeStack) > 0 {
			top.dependents[name] = false // ensure exists
			for n := range deps {
				top.dependents[n] = true
			}
			delete(w.dependentsOf, name)
			return
		}
	}
	for n := range deps {
		target[n] = true
	}
	delete(w.dependentsOf, name)
}

// assignOp returns "=" or "+=" depending on the Assign's Append flag.
func assignOp(a *syntax.Assign) string {
	if a.Append {
		return "+="
	}
	return "="
}

// callExprCommandName returns the first-word literal of a CallExpr, or "".
// For path-qualified commands ("/opt/venv/bin/pip" → "pip") it extracts
// the basename.
func callExprCommandName(c *syntax.CallExpr) string {
	parts := c.Args
	if len(parts) == 0 || len(parts[0].Parts) == 0 {
		return ""
	}
	if lit, ok := parts[0].Parts[0].(*syntax.Lit); ok {
		return basename(lit.Value)
	}
	return ""
}

// basename returns the last component of a file path.
func basename(p string) string {
	if idx := strings.LastIndexByte(p, '/'); idx >= 0 {
		return p[idx+1:]
	}
	return p
}

func redirectTargetWord(w *syntax.Word) string {
	var parts []string
	for _, p := range w.Parts {
		if lit, ok := p.(*syntax.Lit); ok {
			parts = append(parts, lit.Value)
		}
	}
	return strings.Join(parts, "")
}

// --- Token emission dispatch (per mvdan node type) --------------------------

func (w *walker) visitNode(n syntax.Node) {
	switch x := n.(type) {

	// ---- keywords ----

	case *syntax.IfClause:
		isNested := len(w.frames) > 0 && w.frames[len(w.frames)-1] == frameIfClause
		var kw string
		switch {
		case !isNested:
			kw = "if"
		case x.ThenPos.IsValid():
			kw = "elif"
		default:
			kw = "else"
		}
		w.emitToken(Token{Kind: "keyword", Op: kw,
			StartLine: w.posLine(x.Position),
			StartCol:  w.posCol(x.Position),
			EndLine:   w.posLine(x.Position),
			EndCol:    w.posCol(x.Position) + len(kw),
		})
		if x.ThenPos.IsValid() {
			w.emitToken(Token{Kind: "keyword", Op: "then",
				StartLine: w.posLine(x.ThenPos),
				StartCol:  w.posCol(x.ThenPos),
				EndLine:   w.posLine(x.ThenPos),
				EndCol:    w.posCol(x.ThenPos) + 4,
			})
		}
		if !isNested {
			w.emitToken(Token{Kind: "keyword", Op: "fi",
				StartLine: w.posLine(x.FiPos),
				StartCol:  w.posCol(x.FiPos),
				EndLine:   w.posLine(x.FiPos),
				EndCol:    w.posCol(x.FiPos) + 2,
			})
		}

	case *syntax.ForClause:
		op := "for"
		if x.Select {
			op = "select"
		}
		w.emitToken(Token{Kind: "keyword", Op: op, StartLine: w.posLine(x.ForPos), StartCol: w.posCol(x.ForPos), EndLine: w.posLine(x.ForPos), EndCol: w.posCol(x.ForPos) + len(op)})
		w.emitToken(Token{Kind: "keyword", Op: "do", StartLine: w.posLine(x.DoPos), StartCol: w.posCol(x.DoPos), EndLine: w.posLine(x.DoPos), EndCol: w.posCol(x.DoPos) + 2})
		w.emitToken(Token{Kind: "keyword", Op: "done", StartLine: w.posLine(x.DonePos), StartCol: w.posCol(x.DonePos), EndLine: w.posLine(x.DonePos), EndCol: w.posCol(x.DonePos) + 4})

	case *syntax.WordIter:
		if x.InPos.IsValid() {
			w.emitToken(Token{Kind: "keyword", Op: "in", StartLine: w.posLine(x.InPos), StartCol: w.posCol(x.InPos), EndLine: w.posLine(x.InPos), EndCol: w.posCol(x.InPos) + 2})
		}
		if x.Name != nil {
			w.emitToken(Token{Kind: "var-name", StartLine: w.posLine(x.Name.Pos()), StartCol: w.posCol(x.Name.Pos()), EndLine: w.posLine(x.Name.End()), EndCol: w.posCol(x.Name.End())})
		}

	case *syntax.CStyleLoop:
		w.emitToken(Token{Kind: "operator", Op: "((", StartLine: w.posLine(x.Lparen), StartCol: w.posCol(x.Lparen), EndLine: w.posLine(x.Lparen), EndCol: w.posCol(x.Lparen) + 2})
		w.emitToken(Token{Kind: "operator", Op: "))", StartLine: w.posLine(x.Rparen), StartCol: w.posCol(x.Rparen), EndLine: w.posLine(x.Rparen), EndCol: w.posCol(x.Rparen) + 2})

	case *syntax.WhileClause:
	op := "while"
		if x.Until {
			op = "until"
		}
		w.emitToken(Token{Kind: "keyword", Op: op, StartLine: w.posLine(x.WhilePos), StartCol: w.posCol(x.WhilePos), EndLine: w.posLine(x.WhilePos), EndCol: w.posCol(x.WhilePos) + len(op)})
		w.emitToken(Token{Kind: "keyword", Op: "do", StartLine: w.posLine(x.DoPos), StartCol: w.posCol(x.DoPos), EndLine: w.posLine(x.DoPos), EndCol: w.posCol(x.DoPos) + 2})
		w.emitToken(Token{Kind: "keyword", Op: "done", StartLine: w.posLine(x.DonePos), StartCol: w.posCol(x.DonePos), EndLine: w.posLine(x.DonePos), EndCol: w.posCol(x.DonePos) + 4})

	case *syntax.CaseClause:
		w.emitToken(Token{Kind: "keyword", Op: "case", StartLine: w.posLine(x.Case), StartCol: w.posCol(x.Case), EndLine: w.posLine(x.Case), EndCol: w.posCol(x.Case) + 4})
		if x.In.IsValid() {
			w.emitToken(Token{Kind: "keyword", Op: "in", StartLine: w.posLine(x.In), StartCol: w.posCol(x.In), EndLine: w.posLine(x.In), EndCol: w.posCol(x.In) + 2})
		}
		w.emitToken(Token{Kind: "keyword", Op: "esac", StartLine: w.posLine(x.Esac), StartCol: w.posCol(x.Esac), EndLine: w.posLine(x.Esac), EndCol: w.posCol(x.Esac) + 4})

	case *syntax.CaseItem:
		w.emitToken(Token{Kind: "operator", Op: x.Op.String(), StartLine: w.posLine(x.OpPos), StartCol: w.posCol(x.OpPos), EndLine: w.posLine(x.OpPos), EndCol: w.posCol(x.OpPos) + len(x.Op.String())})

	case *syntax.Block:
		w.emitToken(Token{Kind: "operator", Op: "{", StartLine: w.posLine(x.Lbrace), StartCol: w.posCol(x.Lbrace), EndLine: w.posLine(x.Lbrace), EndCol: w.posCol(x.Lbrace) + 1})
		w.emitToken(Token{Kind: "operator", Op: "}", StartLine: w.posLine(x.Rbrace), StartCol: w.posCol(x.Rbrace), EndLine: w.posLine(x.Rbrace), EndCol: w.posCol(x.Rbrace) + 1})

	case *syntax.Subshell:
		w.emitToken(Token{Kind: "operator", Op: "(", StartLine: w.posLine(x.Lparen), StartCol: w.posCol(x.Lparen), EndLine: w.posLine(x.Lparen), EndCol: w.posCol(x.Lparen) + 1})
		w.emitToken(Token{Kind: "operator", Op: ")", StartLine: w.posLine(x.Rparen), StartCol: w.posCol(x.Rparen), EndLine: w.posLine(x.Rparen), EndCol: w.posCol(x.Rparen) + 1})

	case *syntax.ArithmCmd:
		w.emitToken(Token{Kind: "operator", Op: "((", StartLine: w.posLine(x.Left), StartCol: w.posCol(x.Left), EndLine: w.posLine(x.Left), EndCol: w.posCol(x.Left) + 2})
		w.emitToken(Token{Kind: "operator", Op: "))", StartLine: w.posLine(x.Right), StartCol: w.posCol(x.Right), EndLine: w.posLine(x.Right), EndCol: w.posCol(x.Right) + 2})

	// ---- command / assignment tokens ----

	case *syntax.FuncDecl:
		fi := FunctionInfo{
			Name:      x.Name.Value,
			StartLine: w.posLine(x.Pos()),
			EndLine:   w.posLine(x.End()),
			NameSpan: Span{
				StartLine: w.posLine(x.Name.Pos()),
				StartCol:  w.posCol(x.Name.Pos()),
				EndLine:   w.posLine(x.Name.End()),
				EndCol:    w.posCol(x.Name.End()),
			},
		}
		w.funcs = append(w.funcs, fi)

		// "function" keyword (optional)
		if x.RsrvWord {
			w.emitToken(Token{Kind: "keyword", Op: "function", StartLine: w.posLine(x.Position), StartCol: w.posCol(x.Position), EndLine: w.posLine(x.Position), EndCol: w.posCol(x.Position) + 8})
		}
		// function-name token
		w.emitToken(Token{Kind: "function-name", StartLine: w.posLine(x.Name.Pos()), StartCol: w.posCol(x.Name.Pos()), EndLine: w.posLine(x.Name.End()), EndCol: w.posCol(x.Name.End())})

		// Add to function-call detection BEFORE recursing into the body
		w.addFuncName(x.Name.Value)

		// Push scope frame; pop after body (syntax.Walk handles the nil callback)
		w.scopeStack = append(w.scopeStack, funcScope{name: x.Name.Value, dependents: map[string]bool{}})

	case *syntax.CallExpr:
		cmdName := callExprCommandName(x)

		// Detect unset -f
		if cmdName == "unset" {
			seenF := false
			for _, arg := range x.Args {
				if lit, ok := arg.Parts[0].(*syntax.Lit); ok {
					if !seenF && lit.Value == "-f" {
						seenF = true
						continue
					}
					if seenF {
						w.removeFuncName(lit.Value)
					}
				}
			}
		}

		// Handle $STD-like prefix (variable as command prefix)
		if cmdName == "" && len(x.Args) > 1 {
			if _, ok := x.Args[0].Parts[0].(*syntax.ParamExp); ok {
				inner := &syntax.CallExpr{Args: x.Args[1:]}
				w.visitNode(inner)
				return
			}
		}

		// Flag detection (preserving existing behavior)
		switch cmdName {
		case "sudo":
			w.flags.Sudo = true
			if len(x.Args) > 1 {
				inner := &syntax.CallExpr{Args: x.Args[1:]}
				w.visitNode(inner)
			}
			return
		case "eval":
			w.flags.Eval = true
		case "docker", "docker-compose":
			w.flags.Docker = true
		case "podman":
			w.flags.Podman = true
		case "npm", "npx":
			w.flags.NPM = true
		case "yarn":
			w.flags.Yarn = true
		case "pnpm":
			w.flags.Pnpm = true
		case "pip", "pip3":
			if len(x.Args) > 1 {
				if lit, ok := x.Args[1].Parts[0].(*syntax.Lit); ok && lit.Value == "install" {
					w.flags.Pip = true
				}
			}
		case "cargo":
			if len(x.Args) > 1 {
				if lit, ok := x.Args[1].Parts[0].(*syntax.Lit); ok {
					if lit.Value == "install" || lit.Value == "build" {
						w.flags.Cargo = true
					}
				}
			}
		case "go":
			if len(x.Args) > 1 {
				if lit, ok := x.Args[1].Parts[0].(*syntax.Lit); ok {
					if lit.Value == "install" || lit.Value == "build" || lit.Value == "run" || lit.Value == "get" {
						w.flags.Go = true
					}
				}
			}
		case "git":
			gitCmds := map[string]bool{"clone": true, "pull": true, "fetch": true, "checkout": true,
				"init": true, "remote": true, "add": true, "commit": true, "push": true, "branch": true,
				"log": true, "diff": true, "submodule": true, "config": true, "stash": true, "merge": true}
			if len(x.Args) > 1 {
				if lit, ok := x.Args[1].Parts[0].(*syntax.Lit); ok && gitCmds[lit.Value] {
					w.flags.Git = true
				}
			}
		}

		// Shell-eval depth push (cover bash/sh, eval, source, .)
		if shellEvalCommands[cmdName] {
			w.evalStack = append(w.evalStack, Span{
				StartLine: w.posLine(x.Pos()),
				StartCol:  w.posCol(x.Pos()),
				EndLine:   w.posLine(x.End()),
				EndCol:    w.posCol(x.End()),
				Kind:      cmdName,
			})
			w.shellEvalDepth++
			w.pushedEval = true
		}

		// Download detection (exclude framework bootstrap line)
		if downloadCommands[cmdName] {
			if w.posLine(x.Pos()) != w.bootLine {
				w.hasDownload = true
				w.downloadSpans = append(w.downloadSpans, Span{
					StartLine: w.posLine(x.Pos()),
					StartCol:  w.posCol(x.Pos()),
					EndLine:   w.posLine(x.End()),
					EndCol:    w.posCol(x.End()),
					Kind:      "download",
				})
				if w.shellEvalDepth > 0 && len(w.evalStack) > 0 {
					outer := w.evalStack[0]
					w.extSpans = append(w.extSpans, outer)
				}
			}
		}

		// Keep CmdSubst detection inside bash/sh -c for eval flag
		if cmdName == "bash" || cmdName == "sh" {
			for i := 1; i < len(x.Args)-1; i++ {
				if lit, ok := x.Args[i].Parts[0].(*syntax.Lit); ok && lit.Value == "-c" {
					if i+1 < len(x.Args) {
						syntax.Walk(x.Args[i+1], func(n syntax.Node) bool {
							if _, ok := n.(*syntax.CmdSubst); ok {
								w.flags.Eval = true
								return false
							}
							return true
						})
					}
				}
			}
		}

		// Emit command or function-call token for the first word
		if cmdName != "" {
			firstWord := x.Args[0]
			if w.isFuncCall(cmdName) {
				w.emitToken(Token{Kind: "function-call", StartLine: w.posLine(firstWord.Pos()), StartCol: w.posCol(firstWord.Pos()), EndLine: w.posLine(firstWord.End()), EndCol: w.posCol(firstWord.End())})
				w.promoteFunc(cmdName)
			} else {
				w.emitToken(Token{Kind: "command", StartLine: w.posLine(firstWord.Pos()), StartCol: w.posCol(firstWord.Pos()), EndLine: w.posLine(firstWord.End()), EndCol: w.posCol(firstWord.End())})
			}
		}

	case *syntax.Assign:
		if x.Name != nil {
			w.emitToken(Token{Kind: "var-assign", Op: assignOp(x), StartLine: w.posLine(x.Pos()), StartCol: w.posCol(x.Pos()), EndLine: w.posLine(x.End()), EndCol: w.posCol(x.End())})
			w.emitToken(Token{Kind: "var-name", StartLine: w.posLine(x.Name.Pos()), StartCol: w.posCol(x.Name.Pos()), EndLine: w.posLine(x.Name.End()), EndCol: w.posCol(x.Name.End())})
		}

	case *syntax.DeclClause:
		if x.Variant != nil {
			w.emitToken(Token{Kind: "keyword", Op: x.Variant.Value, StartLine: w.posLine(x.Variant.Pos()), StartCol: w.posCol(x.Variant.Pos()), EndLine: w.posLine(x.Variant.End()), EndCol: w.posCol(x.Variant.End())})
		}

	case *syntax.TimeClause:
		w.emitToken(Token{Kind: "keyword", Op: "time", StartLine: w.posLine(x.Time), StartCol: w.posCol(x.Time), EndLine: w.posLine(x.Time), EndCol: w.posCol(x.Time) + 4})

	case *syntax.CoprocClause:
		w.emitToken(Token{Kind: "keyword", Op: "coproc", StartLine: w.posLine(x.Coproc), StartCol: w.posCol(x.Coproc), EndLine: w.posLine(x.Coproc), EndCol: w.posCol(x.Coproc) + 6})

	case *syntax.LetClause:
		w.emitToken(Token{Kind: "keyword", Op: "let", StartLine: w.posLine(x.Let), StartCol: w.posCol(x.Let), EndLine: w.posLine(x.Let), EndCol: w.posCol(x.Let) + 3})

	// ---- operators and statement boundaries ----

	case *syntax.Stmt:
		if x.Negated {
			w.emitToken(Token{Kind: "operator", Op: "!", StartLine: w.posLine(x.Position), StartCol: w.posCol(x.Position), EndLine: w.posLine(x.Position), EndCol: w.posCol(x.Position) + 1})
		}
		if x.Semicolon.IsValid() {
			op := ";"
			if x.Background {
				op = "&"
			} else if x.Coprocess {
				op = "|&"
			} else if x.Disown {
				op = "&!"
			}
			w.emitToken(Token{Kind: "operator", Op: op, StartLine: w.posLine(x.Semicolon), StartCol: w.posCol(x.Semicolon), EndLine: w.posLine(x.Semicolon), EndCol: w.posCol(x.Semicolon) + len(op)})
		}

	case *syntax.BinaryCmd:
		w.emitToken(Token{Kind: "operator", Op: x.Op.String(), StartLine: w.posLine(x.OpPos), StartCol: w.posCol(x.OpPos), EndLine: w.posLine(x.OpPos), EndCol: w.posCol(x.OpPos) + len(x.Op.String())})
		// Pipe detection: external (shell eval) + piped-download (non-shell)
		if x.Op == syntax.Pipe {
			left := getCallExpr(x.X)
			right := getCallExpr(x.Y)
			if right != nil {
				rightCmd := callExprCommandName(right)
				if shellEvalCommands[rightCmd] {
					w.evalStack = append(w.evalStack, Span{
						StartLine: w.posLine(x.Pos()),
						StartCol:  w.posCol(x.Pos()),
						EndLine:   w.posLine(x.End()),
						EndCol:    w.posCol(x.End()),
						Kind:      "pipe_to_shell",
					})
					w.shellEvalDepth++
					w.pushedEval = true
				}
			}
			// Piped-download: curl/wget piped to non-shell
			if left != nil && right != nil {
				leftCmd := callExprCommandName(left)
				rightCmd := callExprCommandName(right)
				if downloadCommands[leftCmd] && !shellEvalCommands[rightCmd] {
					if w.posLine(x.Pos()) != w.bootLine {
						w.pipedDownloadSpans = append(w.pipedDownloadSpans, Span{
							StartLine: w.posLine(x.Pos()),
							StartCol:  w.posCol(x.Pos()),
							EndLine:   w.posLine(x.End()),
							EndCol:    w.posCol(x.End()),
							Kind:      "piped_download",
						})
					}
				}
			}
		}

	case *syntax.Redirect:
		w.emitToken(Token{Kind: "operator", Op: x.Op.String(), StartLine: w.posLine(x.OpPos), StartCol: w.posCol(x.OpPos), EndLine: w.posLine(x.OpPos), EndCol: w.posCol(x.OpPos) + len(x.Op.String())})
		// Heredoc handling — only for Hdoc / DashHdoc
		if x.Op != syntax.Hdoc && x.Op != syntax.DashHdoc {
			return
		}
		if x.Hdoc == nil {
			return
		}
		hd := Heredoc{}
		hd.Op.Line = w.posLine(x.OpPos)
		hd.Op.Col = w.posCol(x.OpPos)
		if x.Op == syntax.DashHdoc {
			hd.Op.Kind = "<<-"
			hd.StripTabs = true
		} else {
			hd.Op.Kind = "<<"
		}
		delimText := ""
		quoted := false
		if len(x.Word.Parts) > 0 {
			switch q := x.Word.Parts[0].(type) {
			case *syntax.Lit:
				delimText = q.Value
				quoted = false
			case *syntax.SglQuoted:
				delimText = q.Value
				quoted = true
			case *syntax.DblQuoted:
				if len(q.Parts) > 0 {
					if lit, ok := q.Parts[0].(*syntax.Lit); ok {
						delimText = lit.Value
					}
				}
				quoted = true
			}
		}
		hd.MarkerStart = Marker{
			Line:     w.posLine(x.Word.Pos()),
			StartCol: w.posCol(x.Word.Pos()),
			EndCol:   w.posCol(x.Word.End()),
			Text:     delimText,
		}
		hd.Expand = !quoted
		hd.Body.StartLine = w.posLine(x.Hdoc.Pos())
		hd.Body.EndLine = w.posLine(x.Hdoc.End()) - 1
		hd.MarkerEnd = Marker{
			Line:     w.posLine(x.Hdoc.End()),
			StartCol: 1,
			EndCol:   1 + len(delimText),
			Text:     delimText,
		}
		w.heredocs = append(w.heredocs, hd)
		// Emit heredoc-delim tokens at both markers
		w.emitToken(Token{Kind: "heredoc-delim", Expand: hd.Expand,
			StartLine: hd.MarkerStart.Line, StartCol: hd.MarkerStart.StartCol,
			EndLine: hd.MarkerStart.Line, EndCol: hd.MarkerStart.EndCol})
		w.emitToken(Token{Kind: "heredoc-delim", Expand: hd.Expand,
			StartLine: hd.MarkerEnd.Line, StartCol: hd.MarkerEnd.StartCol,
			EndLine: hd.MarkerEnd.Line, EndCol: hd.MarkerEnd.EndCol})
		// The heredoc body is walked by syntax.Walk naturally;
		// for expandable heredocs, Parts contain ParamExp/CmdSubst nodes which
		// will be visited and emit their own tokens.

	// ---- test brackets and operators ----

	case *syntax.TestClause:
		w.emitToken(Token{Kind: "operator", Op: "[[", StartLine: w.posLine(x.Left), StartCol: w.posCol(x.Left), EndLine: w.posLine(x.Left), EndCol: w.posCol(x.Left) + 2})
		w.emitToken(Token{Kind: "operator", Op: "]]", StartLine: w.posLine(x.Right), StartCol: w.posCol(x.Right), EndLine: w.posLine(x.Right), EndCol: w.posCol(x.Right) + 2})

	case *syntax.BinaryTest:
		w.emitToken(Token{Kind: "test-operator", Op: x.Op.String(), StartLine: w.posLine(x.OpPos), StartCol: w.posCol(x.OpPos), EndLine: w.posLine(x.OpPos), EndCol: w.posCol(x.OpPos) + len(x.Op.String())})

	case *syntax.UnaryTest:
		w.emitToken(Token{Kind: "test-operator", Op: x.Op.String(), StartLine: w.posLine(x.OpPos), StartCol: w.posCol(x.OpPos), EndLine: w.posLine(x.OpPos), EndCol: w.posCol(x.OpPos) + len(x.Op.String())})

	// ---- expansions and strings ----

	case *syntax.ParamExp:
		w.emitToken(Token{Kind: "param-exp", StartLine: w.posLine(x.Pos()), StartCol: w.posCol(x.Pos()), EndLine: w.posLine(x.End()), EndCol: w.posCol(x.End())})

	case *syntax.CmdSubst:
		w.emitToken(Token{Kind: "cmd-subst", StartLine: w.posLine(x.Pos()), StartCol: w.posCol(x.Pos()), EndLine: w.posLine(x.End()), EndCol: w.posCol(x.End())})

	case *syntax.ProcSubst:
		w.emitToken(Token{Kind: "proc-subst", StartLine: w.posLine(x.Pos()), StartCol: w.posCol(x.Pos()), EndLine: w.posLine(x.End()), EndCol: w.posCol(x.End())})

	case *syntax.ArithmExp:
		w.emitToken(Token{Kind: "arith-exp", StartLine: w.posLine(x.Pos()), StartCol: w.posCol(x.Pos()), EndLine: w.posLine(x.End()), EndCol: w.posCol(x.End())})

	case *syntax.DblQuoted:
		w.emitToken(Token{Kind: "string-dq", StartLine: w.posLine(x.Pos()), StartCol: w.posCol(x.Pos()), EndLine: w.posLine(x.End()), EndCol: w.posCol(x.End())})

	case *syntax.SglQuoted:
		w.emitToken(Token{Kind: "string-sq", StartLine: w.posLine(x.Pos()), StartCol: w.posCol(x.Pos()), EndLine: w.posLine(x.End()), EndCol: w.posCol(x.End())})

	case *syntax.Comment:
		startLine := w.posLine(x.Pos())
		maxEndCol := utf16LenOfLine(w.scriptLines[startLine-1]) + 1
		endCol := w.posCol(x.End())
		if endCol > maxEndCol {
			endCol = maxEndCol
		}
		w.emitToken(Token{Kind: "comment", StartLine: startLine, StartCol: w.posCol(x.Pos()), EndLine: startLine, EndCol: endCol})
	}
}

func getCallExpr(stmt *syntax.Stmt) *syntax.CallExpr {
	if stmt == nil || stmt.Cmd == nil {
		return nil
	}
	if ce, ok := stmt.Cmd.(*syntax.CallExpr); ok {
		return ce
	}
	return nil
}

// --- Service / user extraction ------------------------------------------------

var knownImplicitUsers = map[string]bool{
	"root":     true,
	"nobody":   true,
	"nogroup":  true,
	"daemon":   true,
	"bin":      true,
	"sys":      true,
	"sync":     true,
	"games":    true,
	"man":      true,
	"lp":       true,
	"mail":     true,
	"news":     true,
	"uucp":     true,
	"proxy":    true,
	"www-data": true,
	"postgres": true,
	"mysql":    true,
	"redis":    true,
	"nginx":    true,
	"mosquitto": true,
	"prometheus": true,
	"grafana":  true,
	"caddy":    true,
	"mongodb":  true,
	"influxdb": true,
	"tomcat":   true,
	"jenkins":  true,
	"sonarqube": true,
	"mariadb":  true,
}

func pathFromSourceLine(line string) string {
	idx := strings.Index(line, "/etc/systemd/system/")
	if idx >= 0 {
		rest := line[idx:]
		end := strings.IndexAny(rest, " \t\n\"'")
		if end < 0 {
			end = len(rest)
		}
		return rest[:end]
	}
	idx = strings.Index(line, "/etc/init.d/")
	if idx >= 0 {
		rest := line[idx:]
		end := strings.IndexAny(rest, " \t\n\"'")
		if end < 0 {
			end = len(rest)
		}
		return rest[:end]
	}
	idx = strings.Index(line, "/etc/sysusers.d/")
	if idx >= 0 {
		rest := line[idx:]
		end := strings.IndexAny(rest, " \t\n\"'")
		if end < 0 {
			end = len(rest)
		}
		return rest[:end]
	}
	return ""
}

func isSystemdBody(body string) bool {
	return strings.Contains(body, "[Service]") || strings.Contains(body, "[Unit]")
}

func isOpenRCBody(body string) bool {
	return strings.Contains(body, "#/sbin/openrc-run") ||
		strings.Contains(body, "command_args") ||
		strings.Contains(body, "command_user") ||
		strings.Contains(body, "command_background")
}

func extractSystemdServices(heredocs []Heredoc, lines []string) []SystemdService {
	seen := map[string]bool{}
	services := []SystemdService{}
	for _, hd := range heredocs {
		body := strings.Join(lines[hd.Body.StartLine-1:hd.Body.EndLine], "\n")
		if !isSystemdBody(body) {
			continue
		}
		sourceLine := lines[hd.Op.Line-1]
		path := pathFromSourceLine(sourceLine)
		if path == "" {
			continue
		}
		name := basename(path)
		if !strings.HasSuffix(name, ".service") && !strings.HasSuffix(name, ".timer") && !strings.HasSuffix(name, ".socket") {
			continue
		}
		if seen[name] {
			continue
		}
		seen[name] = true
		user := "root"
		for _, bline := range strings.Split(body, "\n") {
			trimmed := strings.TrimSpace(bline)
			if strings.HasPrefix(trimmed, "User=") {
				user = strings.TrimPrefix(trimmed, "User=")
				user = strings.TrimSpace(user)
				break
			}
		}
		services = append(services, SystemdService{
			Name:     name,
			Path:     path,
			User:     user,
			Required: true,
		})
	}
	return services
}

func extractOpenRCServices(heredocs []Heredoc, lines []string) []OpenRCService {
	seen := map[string]bool{}
	services := []OpenRCService{}
	for _, hd := range heredocs {
		body := strings.Join(lines[hd.Body.StartLine-1:hd.Body.EndLine], "\n")
		if !isOpenRCBody(body) {
			continue
		}
		sourceLine := lines[hd.Op.Line-1]
		path := pathFromSourceLine(sourceLine)
		if path == "" {
			continue
		}
		name := basename(path)
		if seen[name] {
			continue
		}
		seen[name] = true
		user := "root"
		for _, bline := range strings.Split(body, "\n") {
			trimmed := strings.TrimSpace(bline)
			if strings.HasPrefix(trimmed, "command_user") {
				eqIdx := strings.Index(trimmed, "=")
				if eqIdx >= 0 {
					user = strings.TrimSpace(trimmed[eqIdx+1:])
					if q := strings.Trim(user, `"'`); q != user {
						user = q
					}
				}
				break
			}
		}

		services = append(services, OpenRCService{
			Name:     name,
			Path:     path,
			User:     user,
			Required: true,
		})
	}
	return services
}

func extractUserCreations(lines []string) map[string]ScriptUser {
	users := map[string]ScriptUser{}
	for li, line := range lines {
		trimmed := strings.TrimSpace(line)
		fields := strings.Fields(trimmed)

		for fi, f := range fields {
			if f != "useradd" && f != "adduser" {
				continue
			}
			// Skip Debian interactive adduser (no flags, first-arg-is-username mode) when it's
			// clearly the system variant (has --system flag elsewhere)
			if f == "adduser" {
				hasSystem := false
				for _, af := range fields {
					if af == "--system" || af == "--group" || af == "-D" || af == "-H" {
						hasSystem = true
						break
					}
				}
				if !hasSystem {
					continue
				}
			}
			// Find the username: for useradd/adduser --system, the
			// username is the last positional argument. Scan from the end
			// to skip flags/values/quoted-strings that may be split by spaces.
			userName := ""
			for ai := len(fields) - 1; ai > fi; ai-- {
				arg := fields[ai]
				userName = ""
				if strings.HasPrefix(arg, "-") || strings.HasPrefix(arg, "$") || arg == "STDL" {
					continue
				}
				// Skip shell operators (continue past them in reverse)
				if arg == "||" || arg == "&&" || arg == ";" || arg == "|" {
					continue
				}
				// Skip quote fragments from split quoted strings
				if strings.HasPrefix(arg, "'") || strings.HasPrefix(arg, "\"") {
					continue
				}
				// Skip shell builtins and path-like tokens
				if arg == "true" || arg == "false" {
					continue
				}
				userName = strings.Trim(arg, `"'`)
				userName = strings.TrimSuffix(userName, "`")
				if userName != "" && !strings.Contains(userName, "/") {
					break
				}
			}
			if userName != "" {
				if _, exists := users[userName]; !exists {
					users[userName] = ScriptUser{
						Name:   userName,
						Source: f,
						Line:   li + 1,
					}
				}
			}
			break
		}
	}
	return users
}

func resolveUsers(userCreations map[string]ScriptUser, systemdSvcs []SystemdService, openrcSvcs []OpenRCService) []ScriptUser {
	seen := map[string]bool{}
	result := []ScriptUser{}

	for name, u := range userCreations {
		result = append(result, u)
		seen[name] = true
	}

	for _, svc := range systemdSvcs {
		if svc.User == "" || svc.User == "root" || seen[svc.User] {
			continue
		}
		source := "unknown"
		if knownImplicitUsers[svc.User] {
			source = "implicit"
		}
		result = append(result, ScriptUser{
			Name:   svc.User,
			Source: source,
		})
		seen[svc.User] = true
	}

	for _, svc := range openrcSvcs {
		if svc.User == "" || svc.User == "root" || seen[svc.User] {
			continue
		}
		source := "unknown"
		if knownImplicitUsers[svc.User] {
			source = "implicit"
		}
		result = append(result, ScriptUser{
			Name:   svc.User,
			Source: source,
		})
		seen[svc.User] = true
	}

	// Ensure root is always in the list if any service references it or runs as root by default
	hasRoot := false
	for _, svc := range systemdSvcs {
		if svc.User == "" || svc.User == "root" {
			hasRoot = true
			break
		}
	}
	if !hasRoot {
		for _, svc := range openrcSvcs {
			if svc.User == "" || svc.User == "root" {
				hasRoot = true
				break
			}
		}
	}
	if hasRoot && !seen["root"] {
		result = append(result, ScriptUser{Name: "root", Source: "implicit"})
		seen["root"] = true
	}

	return result
}

func extractInteractivePrompts(lines []string) []InteractivePrompt {
	prompts := []InteractivePrompt{}
	whiptailCmds := map[string]bool{"whiptail": true, "dialog": true}

	for li, line := range lines {
		trimmed := strings.TrimSpace(line)
		fields := strings.Fields(trimmed)
		for fi, f := range fields {
			if fi == 0 && whiptailCmds[f] {
				kind := ""
				var text string
				for ai := fi + 1; ai < len(fields); ai++ {
					arg := strings.Trim(fields[ai], `"'`)
					before, _, _ := strings.Cut(fields[ai], "=")
					if before == "--yesno" {
						kind = "yesno"
						continue
					}
					if before == "--menu" {
						kind = "menu"
						continue
					}
					if before == "--inputbox" {
						kind = "inputbox"
						continue
					}
					if before == "--passwordbox" {
						kind = "passwordbox"
						continue
					}
					if kind != "" && text == "" && !strings.HasPrefix(arg, "-") {
						text = arg
						break
					}
				}
				if kind != "" {
					prompts = append(prompts, InteractivePrompt{
						Kind: kind,
						Text: text,
						Line: li + 1,
					})
				}
				break
			}
		}
	}
	return prompts
}

// --- Analyze script ----------------------------------------------------------

func analyzeScript(src string, scriptType ScriptType, slug string, violations *[]string) ASTOutput {
	lines := strings.Split(src, "\n")
	totalLines := len(lines)

	parser := syntax.NewParser(syntax.KeepComments(true), syntax.Variant(syntax.LangBash))
	astFile, err := parser.Parse(strings.NewReader(src), slug+".sh")
	if err != nil {
		*violations = append(*violations, fmt.Sprintf("PARSE ERROR: scripts/%s/%s.sh: %v", scriptType, slug, err))
		return ASTOutput{Slug: slug, Type: string(scriptType), TotalLines: totalLines, Source: src, SourceLines: lines, SchemaVersion: 2}
	}

	w := &walker{
		src:          src,
		funcs:        []FunctionInfo{},
		assigns:      []Assign{},
		globalRanges:   []LineRange{},
		heredocs:     []Heredoc{},
		extSpans:     []Span{},
		tokens:       []Token{},
		scriptLines:  lines,
		frames:              []frameType{},
		evalStack:           []Span{},
		downloadSpans:       []Span{},
		pipedDownloadSpans:  []Span{},
		mainList:            map[string]bool{},
		scopeStack:   []funcScope{},
		dependentsOf:      map[string]map[string]bool{},
		heredocOutputs:    map[int]string{},
	}

	// Bootstrap detection via source text scan
	for li, l := range lines {
		if strings.Contains(l, "source") && strings.Contains(l, "bootstrap/") && strings.Contains(l, "curl") {
			w.bootLine = li + 1
			break
		}
	}

	// Walk the AST, emitting tokens.  We maintain a frame stack to match
	// node entry with exit (pop).  Since syntax.Walk calls the callback
	// with nil exactly once per entered node, the pops are 1:1 with
	// pushes.
	syntax.Walk(astFile, func(n syntax.Node) bool {
		if n == nil {
			if len(w.frames) > 0 {
				f := w.frames[len(w.frames)-1]
				w.frames = w.frames[:len(w.frames)-1]
				switch f {
				case frameFuncDecl:
					if len(w.scopeStack) > 0 {
						topDep := w.scopeStack[len(w.scopeStack)-1]
						w.scopeStack = w.scopeStack[:len(w.scopeStack)-1]
						if topDep.name != "" {
							w.dependentsOf[topDep.name] = topDep.dependents
						}
					}
				case frameShellEval:
					if w.shellEvalDepth > 0 {
						w.shellEvalDepth--
					}
					if len(w.evalStack) > 0 {
						w.evalStack = w.evalStack[:len(w.evalStack)-1]
					}
				}
			}
			return true
		}

		w.visitNode(n)

		if w.pushedEval {
			w.frames = append(w.frames, frameShellEval)
			w.pushedEval = false
		} else {
			switch n.(type) {
			case *syntax.FuncDecl:
				w.frames = append(w.frames, frameFuncDecl)
			case *syntax.IfClause:
				w.frames = append(w.frames, frameIfClause)
			default:
				w.frames = append(w.frames, frameOther)
			}
		}
		return true
	})

	// Sort tokens deterministically
	sort.Slice(w.tokens, func(i, j int) bool {
		a, b := w.tokens[i], w.tokens[j]
		if a.StartLine != b.StartLine {
			return a.StartLine < b.StartLine
		}
		if a.StartCol != b.StartCol {
			return a.StartCol < b.StartCol
		}
		if a.EndLine != b.EndLine {
			return a.EndLine > b.EndLine // outer first
		}
		return a.EndCol > b.EndCol
	})

	// Top-level statement analysis for assigns, global_ranges, REPO_BASE
	repoBaseFound := false
	repoBaseFirstLine := 0
	repoBaseFirstCol := 0
	firstRealStmtLine := 0

	for _, stmt := range astFile.Stmts {
		stmtLine := w.posLine(stmt.Pos())
		if firstRealStmtLine == 0 {
			firstRealStmtLine = stmtLine
		}

		if ce, ok := stmt.Cmd.(*syntax.CallExpr); ok {
			for _, as := range ce.Assigns {
				name := ""
				if as.Name != nil {
					name = as.Name.Value
				}
				hasCmd := false
				isParamDefault := false
				if as.Value != nil {
					for _, part := range as.Value.Parts {
						switch part.(type) {
						case *syntax.CmdSubst:
							hasCmd = true
						}
						if pe, ok := part.(*syntax.ParamExp); ok {
							if pe.Exp != nil && pe.Exp.Op == syntax.DefaultUnsetOrNull {
								isParamDefault = true
							}
						}
					}
				}
				a := Assign{
					Name:              name,
					Line:              w.posLine(as.Pos()),
					StartCol:          w.posCol(as.Pos()),
					EndCol:            w.posCol(as.End()),
					ValueHasCmdSubst:  hasCmd,
					InBootstrapZone:   false,
					IsRepoBase:        name == "REPO_BASE",
					ValueIsParamDefault: isParamDefault,
				}
				if name == "REPO_BASE" && !repoBaseFound {
					repoBaseFound = true
					repoBaseFirstLine = a.Line
					repoBaseFirstCol = a.StartCol
					a.InBootstrapZone = true
				} else if name == "REPO_BASE" {
					*violations = append(*violations, fmt.Sprintf("  scripts/%s/%s.sh:%d: extra REPO_BASE assignment", string(scriptType), slug, a.Line))
				}
				w.assigns = append(w.assigns, a)
			}

			// Non-assign top-level call (not a function) -> host code
			if len(ce.Assigns) == 0 && !w.insideFunc() && stmtLine != w.bootLine {
				w.globalRanges = append(w.globalRanges, LineRange{StartLine: stmtLine, EndLine: stmtLine})
			}
		}

		// Any other top-level statement type -> host code
		if !w.insideFunc() && stmtLine != w.bootLine {
			switch stmt.Cmd.(type) {
			case *syntax.CallExpr:
				// already handled above
			case *syntax.FuncDecl:
				// handled separately
			case *syntax.BinaryCmd:
				w.globalRanges = append(w.globalRanges, LineRange{StartLine: stmtLine, EndLine: stmtLine})
			default:
				w.globalRanges = append(w.globalRanges, LineRange{StartLine: stmtLine, EndLine: stmtLine})
			}
		}
	}

	// REPO_BASE check
	if w.bootLine > 0 && !repoBaseFound {
		bootRefsRepoBase := false
		for _, l := range lines {
			if strings.Contains(l, "bootstrap/") && strings.Contains(l, "REPO_BASE") {
				bootRefsRepoBase = true
				break
			}
		}
		if !bootRefsRepoBase {
			*violations = append(*violations,
				fmt.Sprintf("  scripts/%s/%s.sh: missing REPO_BASE assignment", string(scriptType), slug))
		}
	} else if repoBaseFound {
		firstFnLine := 0
		for _, f := range w.funcs {
			if firstFnLine == 0 || f.StartLine < firstFnLine {
				firstFnLine = f.StartLine
			}
		}
		if firstFnLine > 0 && repoBaseFirstLine > firstFnLine {
			*violations = append(*violations,
				fmt.Sprintf("  scripts/%s/%s.sh:%d:%d: REPO_BASE after first function (at line %d)", string(scriptType), slug, repoBaseFirstLine, repoBaseFirstCol, firstFnLine))
		}
	}

	// Build hooks & hook order
	hooks := make(map[string]bool)
	for _, name := range hookNames {
		hooks[name] = false
	}
	hookOrder := []string{}
	for _, f := range w.funcs {
		for _, name := range hookNames {
			if f.Name == name {
				hooks[name] = true
				hookOrder = append(hookOrder, name)
			}
		}
	}

	// Merge adjacent host ranges
	merged := []LineRange{}
	for _, h := range w.globalRanges {
		if len(merged) == 0 {
			merged = append(merged, h)
		} else {
			last := &merged[len(merged)-1]
			if h.StartLine <= last.EndLine+1 {
				if h.EndLine > last.EndLine {
					last.EndLine = h.EndLine
				}
			} else {
				merged = append(merged, h)
			}
		}
	}
	w.globalRanges = merged
	hasGlobal := len(w.globalRanges) > 0

	systemdSvcs := extractSystemdServices(w.heredocs, lines)
	openrcSvcs := extractOpenRCServices(w.heredocs, lines)
	userCreations := extractUserCreations(lines)
	users := resolveUsers(userCreations, systemdSvcs, openrcSvcs)
	prompts := extractInteractivePrompts(lines)

	serviceManagers := []string{}
	if len(systemdSvcs) > 0 {
		serviceManagers = append(serviceManagers, "systemd")
	}
	if len(openrcSvcs) > 0 {
		serviceManagers = append(serviceManagers, "openrc")
	}

	return ASTOutput{
		SchemaVersion: 2,
		Slug:         slug,
		Type:         string(scriptType),
		TotalLines:   totalLines,
		Source:       src,
		SourceLines:  lines,
		Functions:    w.funcs,
		Assigns:      w.assigns,
		GlobalRanges:   w.globalRanges,
		Heredocs:     w.heredocs,
		DownloadSpans:       w.downloadSpans,
		PipedDownloadSpans:  w.pipedDownloadSpans,
		ExternalSpans:       w.extSpans,
		Tokens:             w.tokens,
		BootstrapLine:      w.bootLine,
		Hooks:              hooks,
		HookOrder:          hookOrder,
		Flags:              w.flags,
		HasDownload:        w.hasDownload,
		HasPipedDownload:   len(w.pipedDownloadSpans) > 0,
		HasExternal:        len(w.extSpans) > 0,
		HasEval:            w.flags.Eval,
		HasGlobal:          hasGlobal,
		HasBootstrap:       w.bootLine > 0,
		SystemdServices:    systemdSvcs,
		OpenRCServices:     openrcSvcs,
		ServiceManagers:    serviceManagers,
		Users:              users,
		InteractivePrompts: prompts,
	}

	return ASTOutput{
		SchemaVersion: 2,
		Slug:         slug,
		Type:         string(scriptType),
		TotalLines:   totalLines,
		Source:       src,
		SourceLines:  lines,
		Functions:    w.funcs,
		Assigns:      w.assigns,
		GlobalRanges:   w.globalRanges,
		Heredocs:     w.heredocs,
		DownloadSpans:       w.downloadSpans,
		PipedDownloadSpans:  w.pipedDownloadSpans,
		ExternalSpans:       w.extSpans,
		Tokens:             w.tokens,
		BootstrapLine:      w.bootLine,
		Hooks:              hooks,
		HookOrder:          hookOrder,
		Flags:              w.flags,
		HasDownload:        w.hasDownload,
		HasPipedDownload:   len(w.pipedDownloadSpans) > 0,
		HasExternal:        len(w.extSpans) > 0,
		HasEval:            w.flags.Eval,
		HasGlobal:          hasGlobal,
		HasBootstrap:       w.bootLine > 0,
		SystemdServices:    systemdSvcs,
		OpenRCServices:     openrcSvcs,
		ServiceManagers:    serviceManagers,
		Users:              users,
		InteractivePrompts: prompts,
	}
}

// --- Main --------------------------------------------------------------------

func main() {
	root, _ := os.Getwd()
	for {
		if _, err := os.Stat(filepath.Join(root, "_config.yml")); err == nil {
			break
		}
		parent := filepath.Dir(root)
		if parent == root {
			fmt.Fprintf(os.Stderr, "Cannot find project root\n")
			os.Exit(1)
		}
		root = parent
	}

	total := 0
	var allViolations []string

	for _, coll := range collections {
		dir := filepath.Join(root, "scripts", string(coll))
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if e.IsDir() || !strings.HasSuffix(e.Name(), ".sh") {
				continue
			}
			total++
			fpath := filepath.Join(dir, e.Name())
			src, err := os.ReadFile(fpath)
			if err != nil {
				fmt.Fprintf(os.Stderr, "  Error reading %s: %v\n", fpath, err)
				continue
			}
			slug := strings.TrimSuffix(e.Name(), ".sh")
			result := analyzeScript(string(src), coll, slug, &allViolations)

			outDir := filepath.Join(root, "_ast", string(coll))
			os.MkdirAll(outDir, 0755)
			outPath := filepath.Join(outDir, slug+".json")
			data, _ := json.MarshalIndent(result, "", "  ")
			os.WriteFile(outPath, data, 0644)
		}
	}

	fmt.Fprintf(os.Stderr, "Generated AST files for %d scripts\n", total)

	if len(allViolations) > 0 {
		fmt.Fprintf(os.Stderr, "\n=== REPO_BASE Violations ===\n")
		for _, v := range allViolations {
			fmt.Fprintln(os.Stderr, v)
		}
		os.Exit(1)
	}
}
