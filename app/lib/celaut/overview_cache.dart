import 'package:flutter/foundation.dart';

import '../bridge/api/celaut_home.dart';

/// The last overview that the home screen loaded. The home screen shows it at once when
/// it opens again, while it asks the nodes, so it never waits on an empty page; the Nodes
/// screen reads the credit of each node from it. It lives in memory only.
final overviewCache = ValueNotifier<ComputeOverviewView?>(null);
