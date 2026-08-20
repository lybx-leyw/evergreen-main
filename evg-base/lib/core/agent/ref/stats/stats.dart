/// Port of reasonix/internal/stats.
///
/// Records per-call token usage as append-only daily JSONL files under the
/// user state root, and aggregates them for the usage panel. Only provider
/// usage and turn completions are recorded; files are append-only with a
/// cross-process lock, and a crash mid-line leaves at most one torn trailing
/// line which [decodeRecords] tolerates and skips.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../billing/cost_quote.dart' as billing;
import '../event/event.dart' as event;
import '../filelock/filelock.dart' as filelock;
import '../provider/usage.dart' as provider;
import '../usagecatalog/catalog.dart' as usagecatalog;

part 'record.dart';
part 'query.dart';
part 'recorder.dart';
part 'usage_catalog.dart';
