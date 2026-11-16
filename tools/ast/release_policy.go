package main

import (
	"bytes"
	"fmt"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

// This is a bounded source policy, not a shell control-flow proof. Literal
// checker calls in addon update hooks must use the established direct positive
// if and immediately preserve $? in its else branch. Dynamic command names,
// eval, helper indirection and service/runtime behavior remain outside its view.
func validateAddonReleaseChecks(file *syntax.File, slug string, violations *[]string) {
	for _, stmt := range file.Stmts {
		fn, ok := stmt.Cmd.(*syntax.FuncDecl)
		if !ok || fn.Name.Value != "update_script" {
			continue
		}
		accepted := map[*syntax.CallExpr]bool{}
		var scopeEdges []bool
		blockedScopes := 0
		syntax.Walk(fn.Body, func(node syntax.Node) bool {
			if node == nil {
				if scopeEdges[len(scopeEdges)-1] {
					blockedScopes--
				}
				scopeEdges = scopeEdges[:len(scopeEdges)-1]
				return false
			}
			// A return inside another function, child shell or expansion cannot
			// establish the update hook's terminal status. Do not certify it.
			boundary := false
			switch part := node.(type) {
			case *syntax.FuncDecl, *syntax.Subshell, *syntax.CmdSubst, *syntax.ProcSubst:
				boundary = true
			case *syntax.Stmt:
				boundary = part.Background || part.Coprocess || part.Disown
			case *syntax.BinaryCmd:
				boundary = part.Op.String() == "|" || part.Op.String() == "|&"
			}
			scopeEdges = append(scopeEdges, boundary)
			if boundary {
				blockedScopes++
			}
			if blockedScopes > 0 {
				return true
			}
			clause, ok := node.(*syntax.IfClause)
			if !ok || len(clause.Cond) != 1 || clause.Else == nil || len(clause.Else.Cond) != 0 || clause.Else.Else != nil {
				return true
			}
			condition := clause.Cond[0]
			call, ok := condition.Cmd.(*syntax.CallExpr)
			if !ok || condition.Negated || condition.Background || len(condition.Redirs) != 0 || len(call.Assigns) != 0 || !isReleaseChecker(call) {
				return true
			}
			otherwise := clause.Else.Then
			if len(otherwise) != 2 {
				return true
			}
			decl, ok := otherwise[0].Cmd.(*syntax.DeclClause)
			if !ok || decl.Variant.Value != "local" || len(decl.Args) != 1 || decl.Args[0].Name == nil {
				return true
			}
			name := decl.Args[0].Name.Value
			// Parse the supported contract with the caller's local variable name;
			// compare its complete syntax rather than substring evidence.
			expected, err := syntax.NewParser().Parse(strings.NewReader(fmt.Sprintf("local %s=$?\n[[ \"$%s\" == 1 ]] || return \"$%s\"\n", name, name, name)), "release-contract")
			if err == nil && releaseStatementsEqual(otherwise, expected.Stmts) {
				accepted[call] = true
			}
			return true
		})
		syntax.Walk(fn.Body, func(node syntax.Node) bool {
			call, ok := node.(*syntax.CallExpr)
			if ok && isReleaseChecker(call) && !accepted[call] {
				*violations = append(*violations, fmt.Sprintf("  scripts/addon/%s.sh:%d: release check: cannot establish non-1 error propagation; use direct if/else with local status=$? and [[ \"$status\" == 1 ]] || return \"$status\"", slug, call.Pos().Line()))
			}
			return true
		})
	}
}

func isReleaseChecker(call *syntax.CallExpr) bool {
	if len(call.Args) == 0 {
		return false
	}
	name, literal := sourceIdentityLiteral(call.Args[0])
	return literal && name == "check_for_gh_release"
}

func releaseStatementsEqual(actual, expected []*syntax.Stmt) bool {
	if len(actual) != len(expected) {
		return false
	}
	for i := range actual {
		var a, b bytes.Buffer
		printer := syntax.NewPrinter()
		if printer.Print(&a, actual[i]) != nil || printer.Print(&b, expected[i]) != nil || a.String() != b.String() {
			return false
		}
	}
	return true
}
