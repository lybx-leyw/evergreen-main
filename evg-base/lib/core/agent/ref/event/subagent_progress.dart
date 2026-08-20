part of 'event.dart';

const subagentProgressPrefix = 'reasonix.subagent.';
const subagentProgressStatusName = '${subagentProgressPrefix}status';
const subagentProgressReasoningName = '${subagentProgressPrefix}reasoning';
const subagentProgressTextName = '${subagentProgressPrefix}text';
const subagentProgressNoticeName = '${subagentProgressPrefix}notice';

bool isReservedSubagentProgressName(String name) =>
    name.startsWith(subagentProgressPrefix);

bool isSubagentProgressName(String name) =>
    name == subagentProgressStatusName ||
    name == subagentProgressReasoningName ||
    name == subagentProgressTextName ||
    name == subagentProgressNoticeName;
