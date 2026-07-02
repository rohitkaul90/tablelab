import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tablelab/equity/card.dart';

import '../../tool/solver/freq_tabulate.dart';

List<int> _b(String s) =>
    s.split(' ').where((t) => t.isNotEmpty).map(parseCard).toList();

/// A hand-constructed dump: flop Ks9h4c, OOP first to act. The CHECK line leads
/// (via an IP check and a 2s turn) to an OOP turn node, so we can verify reach-
/// weighting: QcQd checks the flop 50%, 7c2d checks 80%, and both are marginal-
/// made on the turn — the turn aggregate must skew toward 7c2d's mix.
Map<String, dynamic> _dump() => {
      'node_type': 'action_node',
      'player': 0, // OOP
      'strategy': {
        'actions': ['CHECK', 'BET 5', 'BET 15'],
        'strategy': {
          'Qc Qd': [0.5, 0.3, 0.2], // marginalMade (one pair QQ)
          '7c 2d': [0.8, 0.1, 0.1], // air
        },
      },
      'childrens': {
        'CHECK': {
          'node_type': 'action_node',
          'player': 1, // IP, facing OOP's check
          'strategy': {
            'actions': ['CHECK', 'BET 8'],
            'strategy': {
              'Ad Ah': [0.7, 0.3], // marginalMade (overpair)
            },
          },
          'childrens': {
            'CHECK': {
              'node_type': 'chance_node',
              // Real solver dumps key a chance node's cards under `dealcards`,
              // NOT `childrens` — the tabulator must read dealcards (regression).
              'dealcards': {
                '2s': {
                  'node_type': 'action_node',
                  'player': 0, // OOP, new street (turn)
                  'strategy': {
                    'actions': ['CHECK', 'BET 10'],
                    'strategy': {
                      'Qc Qd': [0.4, 0.6], // still one pair → marginalMade
                      '7c 2d': [0.9, 0.1], // now pairs the 2 → marginalMade
                    },
                  },
                  'childrens': {
                    'CHECK': {'node_type': 'terminal_node'},
                    'BET 10': {'node_type': 'terminal_node'},
                  },
                },
              },
            },
            'BET 8': {'node_type': 'terminal_node'},
          },
        },
        'BET 5': {'node_type': 'terminal_node'},
        'BET 15': {'node_type': 'terminal_node'},
      },
    };

FreqCell _cell(List<FreqCell> cells,
    {required String street,
    required String position,
    required String facing,
    required String handClass}) {
  return cells.firstWhere((c) =>
      c.street == street &&
      c.position == position &&
      c.facing == facing &&
      c.handClass == handClass);
}

void main() {
  group('canonicalActionLabels', () {
    test('ranks bet sizes to small/big and maps the rest', () {
      expect(canonicalActionLabels(['CHECK', 'BET 5', 'BET 15']),
          ['check', 'bet_small', 'bet_big']);
      expect(canonicalActionLabels(['FOLD', 'CALL', 'RAISE 60', 'ALLIN']),
          ['fold', 'call', 'raise', 'allin']);
    });

    test('a lone bet size is just "bet"', () {
      expect(canonicalActionLabels(['CHECK', 'BET 8']), ['check', 'bet']);
    });

    test('three bet sizes give small/mid/big', () {
      expect(canonicalActionLabels(['BET 3', 'BET 9', 'BET 20']),
          ['bet_small', 'bet_mid', 'bet_big']);
    });
  });

  group('tabulateSpot', () {
    // pot0 10, effStack 45 → flop SPR 4.5 → 'medium'. The turn is reached via
    // CHECK→CHECK (no chips added), so the turn SPR is still 4.5 → 'medium'.
    final cells = tabulateSpot(_dump(),
        board: _b('Ks 9h 4c'), pot0: 10, effStack: 45);

    test('flop OOP cells carry each combo mix verbatim (reach 1.0)', () {
      final mm = _cell(cells,
          street: 'flop',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      expect(mm.texture, 'rainbow|unpaired|broadway|disconnected');
      expect(mm.freqs['check'], closeTo(0.5, 1e-9));
      expect(mm.freqs['bet_small'], closeTo(0.3, 1e-9));
      expect(mm.freqs['bet_big'], closeTo(0.2, 1e-9));
      expect(mm.reachWeight, closeTo(1.0, 1e-9));

      final air = _cell(cells,
          street: 'flop',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'air');
      expect(air.freqs['check'], closeTo(0.8, 1e-9));
    });

    test('IP node is tagged position=ip, facing=facing_check', () {
      final ip = _cell(cells,
          street: 'flop',
          position: 'ip',
          facing: 'facing_check',
          handClass: 'marginalMade');
      expect(ip.freqs['check'], closeTo(0.7, 1e-9));
      expect(ip.freqs['bet'], closeTo(0.3, 1e-9));
    });

    test('turn cell texture is recomputed (rainbow → twotone after 2s)', () {
      final t = _cell(cells,
          street: 'turn',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      expect(t.texture, 'twotone|unpaired|broadway|disconnected');
    });

    test('a checked-through turn keeps the flop SPR bucket (medium)', () {
      final flop = _cell(cells,
          street: 'flop',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      final turn = _cell(cells,
          street: 'turn',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      expect(flop.sprBucket, 'medium');
      expect(turn.sprBucket, 'medium'); // CHECK→CHECK adds no chips
    });

    test('turn aggregate is REACH-weighted by flop-check frequency', () {
      // QcQd reaches the turn-check node with reach 0.5, 7c2d with 0.8.
      //   check = (0.5·0.4 + 0.8·0.9) / (0.5+0.8) = 0.92/1.3 = 0.70769…
      //   bet   = (0.5·0.6 + 0.8·0.1) / 1.3        = 0.38/1.3 = 0.29231…
      // A naive (unweighted) average would give check 0.65 — distinct, so this
      // pins the reach-weighting, not just an average.
      final t = _cell(cells,
          street: 'turn',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      expect(t.freqs['check'], closeTo(0.92 / 1.3, 1e-6));
      expect(t.freqs['bet'], closeTo(0.38 / 1.3, 1e-6));
      expect(t.reachWeight, closeTo(1.3, 1e-9));
      expect(t.freqs['check'], isNot(closeTo(0.65, 1e-2)));
    });

    test('maxBoardLen caps the walk depth (no turn cells at flop-only)', () {
      final flopOnly = tabulateSpot(_dump(),
          board: _b('Ks 9h 4c'), pot0: 10, effStack: 45, maxBoardLen: 3);
      expect(flopOnly.any((c) => c.street == 'turn'), isFalse);
      expect(flopOnly.any((c) => c.street == 'flop'), isTrue);
    });
  });

  // A bet-call flop line grows the pot and shrinks stacks, so the turn sits in a
  // SHALLOWER SPR bucket than the flop — the cell must be tagged by its own
  // street's SPR (what the live villain_range path computes), not the flop regime.
  group('tabulateSpot per-street SPR', () {
    // flop Ks9h4c, pot 10, effStack 60 → flop SPR 6 → 'medium'.
    // OOP bets 7.5 (75% pot), IP calls → pot 25, each committed 7.5,
    // remaining 52.5 → turn SPR 52.5/25 = 2.1 → 'shallow'.
    Map<String, dynamic> betCallDump() => {
          'node_type': 'action_node',
          'player': 0, // OOP
          'strategy': {
            'actions': ['CHECK', 'BET 7.5'],
            'strategy': {
              'Qc Qd': [0.3, 0.7], // marginalMade
            },
          },
          'childrens': {
            'CHECK': {'node_type': 'terminal_node'},
            'BET 7.5': {
              'node_type': 'action_node',
              'player': 1, // IP, facing the bet
              'strategy': {
                'actions': ['FOLD', 'CALL'],
                'strategy': {
                  'Ad Ah': [0.2, 0.8],
                },
              },
              'childrens': {
                'FOLD': {'node_type': 'terminal_node'},
                'CALL': {
                  'node_type': 'chance_node',
                  'dealcards': {
                    '2c': {
                      'node_type': 'action_node',
                      'player': 0, // OOP, turn
                      'strategy': {
                        'actions': ['CHECK', 'BET 12'],
                        'strategy': {
                          'Qc Qd': [0.5, 0.5], // still one pair → marginalMade
                        },
                      },
                      'childrens': {
                        'CHECK': {'node_type': 'terminal_node'},
                        'BET 12': {'node_type': 'terminal_node'},
                      },
                    },
                  },
                },
              },
            },
          },
        };

    final cells =
        tabulateSpot(betCallDump(), board: _b('Ks 9h 4c'), pot0: 10, effStack: 60);

    test('flop is medium, turn drops to shallow after a 75%-pot bet-call', () {
      final flop = _cell(cells,
          street: 'flop',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      final turn = _cell(cells,
          street: 'turn',
          position: 'oop',
          facing: 'first_to_act',
          handClass: 'marginalMade');
      expect(flop.sprBucket, 'medium');
      expect(turn.sprBucket, 'shallow');
    });
  });

  // A faced bet's `facing` key must use ABSOLUTE pot-fraction size buckets
  // (shared betSizeBucket: small <=45%, mid <=70%, big) — NOT the bare 'bet' that
  // canonicalActionLabels emits for a single-size tree — or the live lookup (which
  // keys facing on facing_bet_small/mid/big) can never reach the cell.
  group('tabulateSpot facing-bet size bucketing', () {
    // Flop checks through → turn pot 10. OOP leads turn for 6.6 (66% = 'mid');
    // IP faces it, so IP's node is tagged facing_bet_mid, not facing_bet.
    Map<String, dynamic> turnLeadDump() => {
          'node_type': 'action_node',
          'player': 0, // OOP flop
          'strategy': {
            'actions': ['CHECK', 'BET 5'],
            'strategy': {'Qc Qd': [1.0, 0.0]},
          },
          'childrens': {
            'CHECK': {
              'node_type': 'action_node',
              'player': 1, // IP flop, facing check
              'strategy': {
                'actions': ['CHECK', 'BET 5'],
                'strategy': {'Ad Ah': [1.0, 0.0]},
              },
              'childrens': {
                'CHECK': {
                  'node_type': 'chance_node',
                  'dealcards': {
                    '2c': {
                      'node_type': 'action_node',
                      'player': 0, // OOP turn, leads
                      'strategy': {
                        'actions': ['CHECK', 'BET 6.6'],
                        'strategy': {'Qc Qd': [0.4, 0.6]},
                      },
                      'childrens': {
                        'CHECK': {'node_type': 'terminal_node'},
                        'BET 6.6': {
                          'node_type': 'action_node',
                          'player': 1, // IP turn, FACING the 66% bet
                          'strategy': {
                            'actions': ['FOLD', 'CALL'],
                            'strategy': {'Ad Ah': [0.3, 0.7]},
                          },
                          'childrens': {
                            'FOLD': {'node_type': 'terminal_node'},
                            'CALL': {'node_type': 'terminal_node'},
                          },
                        },
                      },
                    },
                  },
                },
                'BET 5': {'node_type': 'terminal_node'},
              },
            },
            'BET 5': {'node_type': 'terminal_node'},
          },
        };

    final cells =
        tabulateSpot(turnLeadDump(), board: _b('Ks 9h 4c'), pot0: 10, effStack: 60);

    test('faced 66%-pot turn bet is tagged facing_bet_mid (not bare facing_bet)', () {
      final faced = cells.where((c) => c.street == 'turn' && c.position == 'ip');
      expect(faced.map((c) => c.facing), contains('facing_bet_mid'));
      expect(faced.map((c) => c.facing), isNot(contains('facing_bet')));
    });
  });

  // A faced ALL-IN must carry the LIVE lookup's labels: villain_range._heroFacing
  // maps a shove to facing_bet_<bucket> (opening aggression) or facing_raise
  // (aggression over a wager) — it NEVER emits 'facing_allin', so a tabulator
  // that labels shoves that way bakes unreachable cells (the pre-2026-07 gap).
  group('tabulateSpot faced all-in labels', () {
    // OOP open-shoves the flop (no prior street chips) → IP faces a BET, sized
    // by pot fraction: eff 45 into pot 10 = 450% → 'big'. In the CHECK line IP
    // shoves over OOP's check (still opening aggression → bet), and OOP's
    // response node to a bet-then-shove line faces a RAISE.
    Map<String, dynamic> allinDump() => {
          'node_type': 'action_node',
          'player': 0, // OOP flop
          'strategy': {
            'actions': ['CHECK', 'BET 5', 'ALLIN'],
            'strategy': {
              'Qc Qd': [0.5, 0.3, 0.2],
            },
          },
          'childrens': {
            'ALLIN': {
              'node_type': 'action_node',
              'player': 1, // IP facing OOP's OPEN-shove
              'strategy': {
                'actions': ['FOLD', 'CALL'],
                'strategy': {
                  'Ad Ah': [0.1, 0.9],
                },
              },
              'childrens': {
                'FOLD': {'node_type': 'terminal_node'},
                'CALL': {'node_type': 'terminal_node'},
              },
            },
            'BET 5': {
              'node_type': 'action_node',
              'player': 1, // IP facing a 50% bet
              'strategy': {
                'actions': ['FOLD', 'CALL', 'ALLIN'],
                'strategy': {
                  'Ad Ah': [0.1, 0.5, 0.4],
                },
              },
              'childrens': {
                'FOLD': {'node_type': 'terminal_node'},
                'CALL': {'node_type': 'terminal_node'},
                'ALLIN': {
                  'node_type': 'action_node',
                  'player': 0, // OOP facing IP's shove OVER a bet
                  'strategy': {
                    'actions': ['FOLD', 'CALL'],
                    'strategy': {
                      'Qc Qd': [0.6, 0.4],
                    },
                  },
                  'childrens': {
                    'FOLD': {'node_type': 'terminal_node'},
                    'CALL': {'node_type': 'terminal_node'},
                  },
                },
              },
            },
            'CHECK': {'node_type': 'terminal_node'},
          },
        };

    final cells =
        tabulateSpot(allinDump(), board: _b('Ks 9h 4c'), pot0: 10, effStack: 45);

    test('an opening shove is faced as facing_bet_big, never facing_allin', () {
      final ipFacings =
          cells.where((c) => c.position == 'ip').map((c) => c.facing).toSet();
      expect(ipFacings, contains('facing_bet_big'));
      expect(cells.map((c) => c.facing), isNot(contains('facing_allin')));
    });

    test('a shove over a bet is faced as facing_raise', () {
      final oopFacings =
          cells.where((c) => c.position == 'oop').map((c) => c.facing).toSet();
      expect(oopFacings, contains('facing_raise'));
    });
  });

  // A flop→turn→river line (both early streets check through) must produce RIVER
  // cells: the tabulator walks the SECOND chance node and re-buckets the board to
  // a 5-card texture. Locks the river capability — only `maxBoardLen` gated it off
  // (the grid now passes kDumpRounds+2 = 5 for the river cycle).
  group('tabulateSpot river', () {
    Map<String, dynamic> riverDump() => {
          'node_type': 'action_node',
          'player': 0, // OOP flop
          'strategy': {
            'actions': ['CHECK', 'BET 5'],
            'strategy': {'Kc Qd': [1.0, 0.0]}, // top pair → marginalMade
          },
          'childrens': {
            'BET 5': {'node_type': 'terminal_node'},
            'CHECK': {
              'node_type': 'action_node',
              'player': 1, // IP flop facing check
              'strategy': {
                'actions': ['CHECK', 'BET 5'],
                'strategy': {'Ad Ah': [1.0, 0.0]},
              },
              'childrens': {
                'BET 5': {'node_type': 'terminal_node'},
                'CHECK': {
                  'node_type': 'chance_node',
                  'dealcards': {
                    '2s': {
                      'node_type': 'action_node',
                      'player': 0, // OOP turn
                      'strategy': {
                        'actions': ['CHECK', 'BET 6'],
                        'strategy': {'Kc Qd': [1.0, 0.0]},
                      },
                      'childrens': {
                        'BET 6': {'node_type': 'terminal_node'},
                        'CHECK': {
                          'node_type': 'action_node',
                          'player': 1, // IP turn facing check
                          'strategy': {
                            'actions': ['CHECK', 'BET 6'],
                            'strategy': {'Ad Ah': [1.0, 0.0]},
                          },
                          'childrens': {
                            'BET 6': {'node_type': 'terminal_node'},
                            'CHECK': {
                              'node_type': 'chance_node',
                              'dealcards': {
                                '3d': {
                                  'node_type': 'action_node',
                                  'player': 0, // OOP river, first to act
                                  'strategy': {
                                    'actions': ['CHECK', 'BET 7'],
                                    'strategy': {'Kc Qd': [0.6, 0.4]},
                                  },
                                  'childrens': {
                                    'CHECK': {'node_type': 'terminal_node'},
                                    'BET 7': {'node_type': 'terminal_node'},
                                  },
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        };

    // pot0 10, effStack 45 → flop SPR 4.5 'medium'; every street checks through
    // (no chips), so the turn and river stay 'medium'.
    final cells =
        tabulateSpot(riverDump(), board: _b('Ks 9h 4c'), pot0: 10, effStack: 45);

    test('produces a river OOP first_to_act cell at medium SPR', () {
      final river = cells.where((c) =>
          c.street == 'river' &&
          c.position == 'oop' &&
          c.facing == 'first_to_act');
      expect(river, isNotEmpty);
      final r = river.first;
      expect(r.sprBucket, 'medium'); // checked through → flop SPR preserved
      expect(r.freqs['check'], closeTo(0.6, 1e-9));
      expect(r.freqs['bet'], closeTo(0.4, 1e-9));
      expect(r.reachWeight, closeTo(1.0, 1e-9));
    });

    test('river texture is the recomputed 5-card board (not the flop)', () {
      final r = cells.firstWhere((c) => c.street == 'river');
      final flop = cells.firstWhere((c) => c.street == 'flop');
      expect(r.texture, isNot(equals(flop.texture)));
    });

    test('maxBoardLen 4 (turn) caps the walk before the river', () {
      final turnOnly = tabulateSpot(riverDump(),
          board: _b('Ks 9h 4c'), pot0: 10, effStack: 45, maxBoardLen: 4);
      expect(turnOnly.any((c) => c.street == 'river'), isFalse);
      expect(turnOnly.any((c) => c.street == 'turn'), isTrue);
    });
  });

  // The grid runs this file-based entry point inside a worker isolate (so the heavy
  // read + jsonDecode + walk run off the main isolate). It must produce the SAME
  // cells as parsing the dump in-process — it only reads + decodes the file first.
  group('tabulateDumpFile (the tabulator entry point)', () {
    test('matches tabulateSpot on the same dump, via a file', () {
      final tmp = Directory.systemTemp.createTempSync('tabfile_');
      try {
        final path = '${tmp.path}/dump.json';
        File(path).writeAsStringSync(jsonEncode(_dump()));
        final fromFile = tabulateDumpFile(path,
            board: _b('Ks 9h 4c'), pot0: 10, effStack: 45);
        final direct =
            tabulateSpot(_dump(), board: _b('Ks 9h 4c'), pot0: 10, effStack: 45);
        expect(fromFile.length, direct.length);
        final f = _cell(fromFile,
            street: 'turn',
            position: 'oop',
            facing: 'first_to_act',
            handClass: 'marginalMade');
        final d = _cell(direct,
            street: 'turn',
            position: 'oop',
            facing: 'first_to_act',
            handClass: 'marginalMade');
        expect(f.freqs['check'], closeTo(d.freqs['check']!, 1e-12));
        expect(f.reachWeight, closeTo(d.reachWeight, 1e-12));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    // Mirrors the grid worker's new handoff (which replaced Isolate.run — isolates
    // in a group share one heap+GC, so N concurrent deep-river parses thrashed a
    // single GC; a subprocess per spot gives each its own heap). tabulate_one.dart
    // writes the cell JSON to a file (its own process); the grid reads it back.
    // Locks that the toJson → jsonEncode → file → jsonDecode round-trip is faithful.
    test('cell JSON round-trips through a file (the subprocess handoff)', () {
      final tmp = Directory.systemTemp.createTempSync('tabfile2_');
      try {
        final path = '${tmp.path}/dump.json';
        File(path).writeAsStringSync(jsonEncode(_dump()));
        final board = _b('Ks 9h 4c');
        final direct =
            tabulateSpot(_dump(), board: board, pot0: 10, effStack: 45);
        // What tabulate_one.dart writes:
        final outPath = '${tmp.path}/cells.json';
        final cells =
            tabulateDumpFile(path, board: board, pot0: 10, effStack: 45);
        File(outPath)
            .writeAsStringSync(jsonEncode([for (final c in cells) c.toJson()]));
        // What freq_grid.dart reads back:
        final readBack =
            jsonDecode(File(outPath).readAsStringSync()) as List<dynamic>;
        expect(readBack, isNotEmpty);
        expect(readBack.length, direct.length);
        expect((readBack.first as Map).keys,
            containsAll(['street', 'spr_bucket', 'facing', 'hand_class', 'freqs']));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    // Runs the REAL tabulate_one.dart as a subprocess (what the grid does), exactly
    // to catch arg-order / flop-parse regressions cheaply — a bug here otherwise
    // only surfaces on the (expensive, cloud) solve run. Skips if `dart` isn't on
    // PATH; asserts a bug (non-zero exit) rather than masking it.
    test('tabulate_one.dart subprocess writes matching cells', () async {
      final tmp = Directory.systemTemp.createTempSync('tabproc_');
      try {
        final path = '${tmp.path}/dump.json';
        File(path).writeAsStringSync(jsonEncode(_dump()));
        final outPath = '${tmp.path}/cells.json';
        final direct =
            tabulateSpot(_dump(), board: _b('Ks 9h 4c'), pot0: 10, effStack: 45);
        ProcessResult res;
        final packDir = '${tmp.path}/pack';
        try {
          // Exercise the --emit-pack path too (the grid's one-parse-two-outputs
          // handoff): cells file + explorer pack from the same subprocess.
          res = await Process.run('dart', [
            'run',
            'tool/solver/tabulate_one.dart',
            path,
            outPath,
            'Ks9h4c',
            '10',
            '45',
            '5',
            '--emit-pack',
            packDir,
            'srp_late_v_bb',
            'medium',
          ]);
        } on ProcessException {
          markTestSkipped('dart not on PATH — skipping subprocess test');
          return;
        }
        expect(res.exitCode, 0, reason: 'tabulate_one stderr: ${res.stderr}');
        final cells =
            jsonDecode(File(outPath).readAsStringSync()) as List<dynamic>;
        expect(cells.length, direct.length);
        expect((cells.first as Map).keys,
            containsAll(['street', 'spr_bucket', 'facing', 'hand_class', 'freqs']));
        // The pack landed beside the cells: manifest + at least the flop chunk.
        expect(File('$packDir/manifest.json').existsSync(), isTrue,
            reason: '--emit-pack wrote no manifest');
        expect(File('$packDir/flop.bin.gz').existsSync(), isTrue);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
