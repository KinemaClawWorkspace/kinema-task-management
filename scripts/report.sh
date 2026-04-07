#!/bin/bash
# report.sh - Generate daily KinemaTasks report (outputs to stdout)
#
# Usage: report.sh [TASK_DIR]
#   TASK_DIR: defaults to ~/.openclaw/workspace/kinema-tasks
#
# Reads last snapshot, scans active/, generates current status + diff report.
# Output should be sent to chat channel by the calling Agent.

TASK_DIR="${1:-$HOME/.openclaw/workspace/kinema-tasks}"
ACTIVE_DIR="$TASK_DIR/active"
ARCHIVE_DIR="$TASK_DIR/archived"
SNAP_DIR="$TASK_DIR/snapshots"

TODAY=$(TZ=Asia/Shanghai date +%Y-%m-%d)
TODAY_TS=$(TZ=Asia/Shanghai date -d "$TODAY" +%s)
TODAY_DISPLAY=$(TZ=Asia/Shanghai date +"%-m月%-d日")

# --- Helper: time hint for a task ---
# Args: $1=due_date (YYYY-MM-DD or — or empty)
# Prints: time hint string or empty
time_hint() {
  local due="$1"
  [ -z "$due" ] || [ "$due" = "—" ] && return
  local due_ts
  due_ts=$(TZ=Asia/Shanghai date -d "$due" +%s 2>/dev/null) || return
  local diff=$(( (due_ts - TODAY_TS) / 86400 ))

  if [ "$diff" -lt 0 ]; then
    local overdue=$(( -diff ))
    local warn=""
    [ "$overdue" -gt 7 ] && warn=" ⚠️"
    echo " · ${overdue} days overdue${warn}"
  elif [ "$diff" -eq 0 ]; then
    echo " · due today"
  else
    echo " · ${diff} days left"
  fi
}

# --- Helper: sort key for remaining time ---
# Prints seconds until due (negative = overdue), or 999999999 for no due date
sort_key() {
  local due="$1"
  [ -z "$due" ] || [ "$due" = "—" ] && echo 999999999 && return
  local due_ts
  due_ts=$(TZ=Asia/Shanghai date -d "$due" +%s 2>/dev/null) || echo 999999999 && return
  echo $(( due_ts - TODAY_TS ))
}

# --- Find most recent snapshot ---
prev_snap=""
prev_date=""
if [ -d "$SNAP_DIR" ]; then
  prev_snap=$(ls -1 "$SNAP_DIR"/*.md 2>/dev/null | sort -r | head -1)
  if [ -n "$prev_snap" ]; then
    prev_date=$(basename "$prev_snap" .md)
  fi
fi

# --- Collect current active tasks ---
# Format per task: "task_id|title|status|priority|domain|due"
tasks_data=""
if [ -d "$ACTIVE_DIR" ]; then
  for f in "$ACTIVE_DIR"/TASK-*.md; do
    [ -f "$f" ] || continue
    tid=$(basename "$f" .md)
    title=$(grep "^# ${tid}: " "$f" | sed "s/^# ${tid}: //")
    status=$(grep "^| 状态 | " "$f" | sed 's/^| 状态 | \(.*\) |$/\1/')
    priority=$(grep "^| 优先级 | " "$f" | sed 's/^| 优先级 | \(.*\) |$/\1/')
    domain=$(grep "^| 领域 | " "$f" | sed 's/^| 领域 | \(.*\) |$/\1/')
    due=$(grep "^| 截止日期 | " "$f" | sed 's/^| 截止日期 | \(.*\) |$/\1/')
    [ -z "$title" ] && title="(无标题)"
    [ -z "$status" ] && status="Unknown"
    [ -z "$priority" ] && priority="normal"
    [ -z "$domain" ] && domain="—"
    [ -z "$due" ] && due="—"
    tasks_data="${tasks_data}${tid}|${title}|${status}|${priority}|${domain}|${due}
"
  done
fi

# --- Collect recently cancelled from archived ---
declare -A cancelled_tasks
if [ -d "$ARCHIVE_DIR" ]; then
  for f in "$ARCHIVE_DIR"/TASK-*.md; do
    [ -f "$f" ] || continue
    tid=$(basename "$f" .md)
    st=$(grep "^| 状态 | " "$f" | sed 's/^| 状态 | \(.*\) |$/\1/')
    if [ "$st" = "Cancelled" ]; then
      cancelled_tasks["$tid"]=1
    fi
  done
fi

# --- Collect recently done (last 5, by 最后更新 desc) ---
done_list=""
if [ -d "$ARCHIVE_DIR" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    tid=$(echo "$line" | cut -d'|' -f1)
    title=$(echo "$line" | cut -d'|' -f2)
    upd=$(echo "$line" | cut -d'|' -f3)
    done_list="${done_list} ${tid} ${title} | completed: ${upd}\n"
  done < <(
    for f in "$ARCHIVE_DIR"/TASK-*.md; do
      [ -f "$f" ] || continue
      tid=$(basename "$f" .md)
      st=$(grep "^| 状态 | " "$f" | sed 's/^| 状态 | \(.*\) |$/\1/')
      [ "$st" != "Done" ] && continue
      title=$(grep "^# ${tid}: " "$f" | sed "s/^# ${tid}: //")
      upd=$(grep "^| 最后更新 | " "$f" | sed 's/^| 最后更新 | \(.*\) |$/\1/')
      echo "${tid}|${title}|${upd}"
    done | sort -t'|' -k3 -r | head -5
  )
fi

# --- Classify and sort tasks ---
# Group: urgent, normal, low, snoozed, expired
declare -a urgent_list normal_list low_list snoozed_list expired_list

while IFS= read -r line; do
  [ -z "$line" ] && continue
  tid=$(echo "$line" | cut -d'|' -f1)
  title=$(echo "$line" | cut -d'|' -f2)
  status=$(echo "$line" | cut -d'|' -f3)
  priority=$(echo "$line" | cut -d'|' -f4)
  domain=$(echo "$line" | cut -d'|' -f5)
  due=$(echo "$line" | cut -d'|' -f6)

  hint=$(time_hint "$due")
  key=$(sort_key "$due")

  due_display=""
  if [ "$due" != "—" ] && [ -n "$due" ]; then
    due_display=$(TZ=Asia/Shanghai date -d "$due" +"%-m-%-d" 2>/dev/null || echo "$due")
  fi

  # Build entry: "key|status_label|entry_text"
  if [ "$due_display" != "" ]; then
    entry=" 【${status}】 ${tid} ${title} | due: ${due_display}${hint} | ${domain}"
  else
    entry=" 【${status}】 ${tid} ${title} | — | ${domain}"
  fi

  # Classify
  is_expired=0
  is_snoozed=0

  [ "$status" = "Snoozed" ] && is_snoozed=1
  [ "$due" != "—" ] && [ -n "$due" ] && [ "$TODAY" \> "$due" ] && is_expired=1

  if [ "$is_snoozed" -eq 1 ]; then
    # Snoozed: never goes to expired
    snoozed_list+=("${key}|${entry}")
  elif [ "$is_expired" -eq 1 ]; then
    # Expired: sort by overdue desc (most overdue first = smallest key)
    expired_list+=("${key}|${entry}")
  else
    case "$priority" in
      urgent) urgent_list+=("${key}|${entry}") ;;
      normal) normal_list+=("${key}|${entry}") ;;
      low) low_list+=("${key}|${entry}") ;;
    esac
  fi
done <<< "$tasks_data"

# Sort functions: by key ascending
sort_by_key_asc() {
  printf '%s\n' "$@" | sort -t'|' -k1 -n
}
sort_by_key_desc() {
  printf '%s\n' "$@" | sort -t'|' -k1 -rn
}

# --- Count stats ---
in_progress=0
pending=0
snoozed_count=0
total=0

while IFS= read -r line; do
  [ -z "$line" ] && continue
  st=$(echo "$line" | cut -d'|' -f3)
  total=$((total + 1))
  case "$st" in
    "In Progress") in_progress=$((in_progress + 1)) ;;
    "Pending") pending=$((pending + 1)) ;;
    "Snoozed") snoozed_count=$((snoozed_count + 1)) ;;
  esac
done <<< "$tasks_data"

# --- Build report ---
echo "📋 KinemaTasks Daily Report — ${TODAY_DISPLAY}"
echo ""

# Status summary (2-3 sentences)
expired_count=${#expired_list[@]}
urg_with_due=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  key=$(echo "$line" | cut -d'|' -f1)
  [ "$key" -lt 999999999 ] 2>/dev/null && urg_with_due=$((urg_with_due + 1))
done <<< "$(printf '%s\n' "${urgent_list[@]}")"

done_today_count=$(echo -e "$done_list" | grep -c . 2>/dev/null || echo 0)
[ -z "$done_list" ] && done_today_count=0

summary_parts=""
if [ "$total" -eq 0 ]; then
  echo "当前没有活跃任务，一切清闲。"
else
  summary_parts="当前共 ${total} 个活跃任务"
  if [ "$in_progress" -gt 0 ]; then
    summary_parts="${summary_parts}，${in_progress} 个进行中"
  fi
  if [ "$expired_count" -gt 0 ]; then
    summary_parts="${summary_parts}，${expired_count} 个已过期需要关注"
  fi
  if [ "$urg_with_due" -gt 0 ]; then
    summary_parts="${summary_parts}，有紧急任务即将到期"
  fi
  summary_parts="${summary_parts}。"
  echo "$summary_parts"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 当前任务状况"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Print sections
print_sorted_entries() {
  local entries="$1"
  local sort_dir="${2:-asc}"
  if [ -n "$entries" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      # Strip sort key: "key|entry" -> "entry"
      echo "$line" | sed 's/^[^|]*|//'
    done <<< "$entries"
  fi
}

if [ ${#urgent_list[@]} -gt 0 ]; then
  echo "🔴 Urgent"
  print_sorted_entries "$(sort_by_key_asc "${urgent_list[@]}")" asc
  echo ""
fi
if [ ${#normal_list[@]} -gt 0 ]; then
  echo "🟡 Normal"
  print_sorted_entries "$(sort_by_key_asc "${normal_list[@]}")" asc
  echo ""
fi
if [ ${#low_list[@]} -gt 0 ]; then
  echo "🟢 Low"
  print_sorted_entries "$(sort_by_key_asc "${low_list[@]}")" asc
  echo ""
fi
if [ ${#snoozed_list[@]} -gt 0 ]; then
  echo "💤 Snoozed"
  print_sorted_entries "$(sort_by_key_asc "${snoozed_list[@]}")" asc
  echo ""
fi
if [ ${#expired_list[@]} -gt 0 ]; then
  echo "⏰ 已过期"
  print_sorted_entries "$(sort_by_key_desc "${expired_list[@]}")" desc
  echo ""
fi
if [ -n "$done_list" ]; then
  echo "✅ 最近完成"
  echo -e "$done_list"
  echo ""
fi

echo "共 ${total} 个活跃任务 | ${in_progress} In Progress · ${pending} Pending · ${snoozed_count} Snoozed"
echo ""

# --- Diff section (moved to end) ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 昨日变动（${prev_display} → ${TODAY_DISPLAY}）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -n "$prev_snap" ]; then
  prev_display=$(TZ=Asia/Shanghai date -d "$prev_date" +"%-m/%-d" 2>/dev/null || echo "$prev_date")

  # Update the header we already printed
  # Parse previous snapshot task list
  declare -A prev_status prev_priority prev_domain prev_due
  while IFS= read -r line; do
    if [[ "$line" =~ ^\|[[:space:]]TASK- ]]; then
      IFS='|' read -r _ tid _ title _ status _ priority _ domain _ due <<< "$line"
      tid=$(echo "$tid" | tr -d ' ')
      status=$(echo "$status" | tr -d ' ')
      priority=$(echo "$priority" | tr -d ' ')
      domain=$(echo "$domain" | tr -d ' ')
      due=$(echo "$due" | tr -d ' ')
      prev_status["$tid"]="$status"
      prev_priority["$tid"]="$priority"
      prev_domain["$tid"]="$domain"
      prev_due["$tid"]="$due"
    fi
  done < "$prev_snap"

  # Diff: new tasks
  new_tasks=""
  status_changes=""
  field_changes=""
  cancel_changes=""

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    tid=$(echo "$line" | cut -d'|' -f1)
    title=$(echo "$line" | cut -d'|' -f2)
    status=$(echo "$line" | cut -d'|' -f3)
    priority=$(echo "$line" | cut -d'|' -f4)
    domain=$(echo "$line" | cut -d'|' -f5)
    due=$(echo "$line" | cut -d'|' -f6)

    if [ -z "${prev_status[$tid]}" ]; then
      new_tasks=" ${tid} ${title} | ${priority} | ${domain}\n${new_tasks}"
    else
      if [ "${status}" != "${prev_status[$tid]}" ]; then
        status_changes=" ${tid} ${prev_status[$tid]} → ${status}\n${status_changes}"
      fi
      field_diff=""
      [ "${priority}" != "${prev_priority[$tid]}" ] && field_diff="${field_diff}优先级 ${prev_priority[$tid]} → ${priority}, "
      [ "${domain}" != "${prev_domain[$tid]}" ] && field_diff="${field_diff}领域 ${prev_domain[$tid]} → ${domain}, "
      [ "${due}" != "${prev_due[$tid]}" ] && field_diff="${field_diff}截止日期 ${prev_due[$tid]} → ${due}, "
      if [ -n "$field_diff" ]; then
        field_diff="${field_diff%, }"
        field_changes=" ${tid} ${field_diff}\n${field_changes}"
      fi
    fi
  done <<< "$tasks_data"

  for tid in "${!prev_status[@]}"; do
    if [ -z "$(echo "$tasks_data" | grep "^${tid}|")" ] && [ -n "${cancelled_tasks[$tid]}" ]; then
      cancel_changes=" ${tid}\n${cancel_changes}"
    fi
  done

  has_diff=0
  if [ -n "$new_tasks" ]; then
    new_count=$(echo -e "$new_tasks" | wc -l)
    echo "新增 (${new_count})"
    echo -e "$new_tasks"
    echo ""
    has_diff=1
  fi
  if [ -n "$status_changes" ]; then
    sc_count=$(echo -e "$status_changes" | wc -l)
    echo "状态变更 (${sc_count})"
    echo -e "$status_changes"
    echo ""
    has_diff=1
  fi
  if [ -n "$field_changes" ]; then
    fc_count=$(echo -e "$field_changes" | wc -l)
    echo "字段变更 (${fc_count})"
    echo -e "$field_changes"
    echo ""
    has_diff=1
  fi
  if [ -n "$cancel_changes" ]; then
    cc_count=$(echo -e "$cancel_changes" | wc -l)
    echo "取消 (${cc_count})"
    echo -e "$cancel_changes"
    echo ""
    has_diff=1
  fi
  if [ "$has_diff" -eq 0 ]; then
    echo "无变动"
    echo ""
  fi
else
  echo "（首次运行，无历史快照可供对比）"
  echo ""
fi
