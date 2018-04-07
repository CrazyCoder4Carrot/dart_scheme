/// It's highly recommended to import this library with the prefix `logic`.
/// e.g. import 'package:cs61a_scheme/logic.dart' as logic;
/// This library does not depend on the implementation library.
library logic;

import 'package:quiver_hashcode/hashcode.dart' show hash2;

import 'package:cs61a_scheme/cs61a_scheme.dart';
export 'package:cs61a_scheme/cs61a_scheme.dart'
    show Pair, PairOrEmpty, SchemeSymbol, nil;

class LogicException extends SchemeException {
  LogicException([msg, showTrace, context]) : super(msg, showTrace, context);
}

int _globalCounter = 0;

class Variable extends SelfEvaluating {
  final String value;
  int tag;
  Variable(this.value);

  factory Variable.fromSymbol(SchemeSymbol sym) {
    if (!sym.value.startsWith('?')) {
      throw new LogicException('Invalid variable $sym');
    }
    return new Variable(sym.value.substring(1));
  }

  /// Finds all variables in a given input
  static Iterable<Variable> findIn(Expression input) sync* {
    if (input is Query) {
      for (Pair relation in input.clauses) {
        yield* findIn(relation);
      }
    } else if (input is Fact) {
      yield* findIn(input.conclusion);
      for (Pair relation in input.hypotheses) {
        yield* findIn(relation);
      }
    } else if (input is Pair) {
      yield* findIn(input.first);
      yield* findIn(input.second);
    } else if (input is Variable) {
      yield input;
    }
  }

  operator ==(v) => v is Variable && value == v.value && tag == v.tag;

  int get hashCode => hash2(value, tag);

  /// Converts so all symbols starting with '?' are converted to variables
  static Expression convert(Expression expr, [int tag]) {
    if (expr is Pair) {
      return new Pair(convert(expr.first, tag), convert(expr.second, tag));
    } else if (expr is SchemeSymbol && expr.value.startsWith('?')) {
      return new Variable.fromSymbol(expr)..tag = tag;
    } else if (expr is SchemeSymbol && expr.value == 'not') {
      return not;
    } else if (expr is Variable) {
      return new Variable(expr.value)..tag = tag;
    }
    return expr;
  }

  toString() => '?$value${tag ?? ""}';
}

class _Negation extends SelfEvaluating {
  const _Negation();

  toString() => 'not';
}

const not = const _Negation();

class Fact extends SelfEvaluating {
  final Pair conclusion;
  final Iterable<Pair> hypotheses;
  Fact._(this.conclusion, this.hypotheses);

  factory Fact(Expression conclusion,
      [Iterable<Expression> hypotheses, int tag]) {
    return new Fact._(Variable.convert(conclusion, tag) as Pair,
        (hypotheses ?? []).map((h) => Variable.convert(h, tag) as Pair));
  }
}

class Query extends SelfEvaluating {
  final Iterable<Pair> clauses;
  Query._(this.clauses);

  factory Query(Iterable<Expression> clauses) {
    return new Query._(clauses.map((h) => Variable.convert(h) as Pair));
  }
}

class Solution extends SelfEvaluating {
  final Map<Variable, Expression> assignments = {};

  toString() =>
      assignments.keys.map((v) => '${v.value}: ${assignments[v]}').join('\t');
}

class LogicEnv extends SelfEvaluating {
  final Solution partial = new Solution();
  final LogicEnv parent;

  LogicEnv(this.parent);

  Expression lookup(Variable variable) {
    return partial.assignments[variable] ?? parent?.lookup(variable);
  }

  Expression completeLookup(Expression expr) {
    if (expr is Variable) {
      var result = lookup(expr);
      if (result == null) return expr;
      return completeLookup(result);
    }
    return expr;
  }
}

Iterable<Solution> evaluate(Query query, List<Fact> facts,
    [int depthLimit = 50]) sync* {
  var run = new _LogicRun(facts, depthLimit);
  for (LogicEnv env in run.searchQuery(query)) {
    var solution = new Solution();
    for (var variable in Variable.findIn(query)) {
      solution.assignments[variable] = run.ground(variable, env);
    }
    yield solution;
  }
}

class _LogicRun {
  final List<Fact> facts;
  final int depthLimit;

  _LogicRun(this.facts, this.depthLimit);

  Iterable<LogicEnv> searchQuery(Query query) sync* {
    _globalCounter = 0;
    yield* search(query.clauses, new LogicEnv(null), 0);
  }

  search(Iterable<Pair> clauses, LogicEnv env, int depth) sync* {
    if (clauses.isEmpty) {
      yield env;
      return;
    }
    if (depth > depthLimit) return;
    Pair clause = clauses.first;
    if (clause.first == not) {
      var grounded = ground(clause.second, env) as Iterable<Pair>;
      if (search(grounded, env, depth).isEmpty) {
        var envHead = new LogicEnv(env);
        yield* search(clauses.skip(1), envHead, depth + 1);
      }
    } else {
      for (var fact in facts) {
        fact = new Fact(fact.conclusion, fact.hypotheses, _globalCounter++);
        var envHead = new LogicEnv(env);
        if (unify(fact.conclusion, clause, envHead)) {
          for (var envRule in search(fact.hypotheses, envHead, depth + 1)) {
            yield* search(clauses.skip(1), envRule, depth + 1);
          }
        }
      }
    }
  }

  Expression ground(Expression expr, LogicEnv env) {
    while (expr is Variable) {
      expr = env.lookup(expr);
    }
    if (expr is Pair) {
      return new Pair(ground(expr.first, env), ground(expr.second, env));
    }
    return expr;
  }

  unify(Expression a, Expression b, LogicEnv env) {
    a = env.completeLookup(a);
    b = env.completeLookup(b);
    if (a == b) {
      return true;
    } else if (a is Variable) {
      env.partial.assignments[a] = b;
      return true;
    } else if (b is Variable) {
      env.partial.assignments[b] = a;
      return true;
    } else if (a is Pair && b is Pair) {
      return unify(a.first, b.first, env) && unify(a.second, b.second, env);
    }
    return false;
  }
}