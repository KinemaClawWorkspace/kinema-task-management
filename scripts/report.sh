#!/bin/bash
# report.sh - Generate daily KinemaTasks report (outputs to stdout)
#
# Usage: report.sh [TASK_DIR]
#   TASK_DIR: defaults to ~/.openclaw/workspace/kinema-tasks
#
# Reads last snapshot, scans active/, generates diff + current status report.
# Output should be sent to chat channel by the calling Agent.

TASK_DIR="${1:-$HOME/.openclaw/workspace/kinema-tasks}"
ACTIVE_DIR="$TASK_DIR/active"
ARCHIVE_DIR="$TASK_DIR/archived"
SNAP_DIR="$TASK_DIR/snapshots"

TODAY=$(TZ=Asia/Shanghai date +%Y-%m-%d)
TODAY_DISPLAY=$(TZ=Asia/Shanghai date +"%-m月%-d日")

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
declare -A cur_status cur_priority cur_domain cur_due cur_title

if [ -d "$ACTIVE_DIR" ]; then
  for f in "$ACTIVE_DIR"/TASK-*.md; do
    [ -f "$f" ] || continue
    tid=$(basename "$f" .md)
    cur_title["$tid"]=$(grep "^# ${tid}: " "$f" | sed "s/^# ${tid}: //")
    cur_status["$tid"]=$(grep "^| 状态 | " "$f" | sed 's/^| 状态 | \(.*\) |$/\1/')
    cur_priority["$tid"]=$(grep "^| 优先级 | " "$f" | sed 's/^| 优先级 | \(.*\) |$/\1/')
    cur_domain["$tid"]=$(grep "^| 领域 | " "$f" | sed 's/^| 领域 | \(.*\) |$/\1/')
    cur_due["$tid"]=$(grep "^| 截止日期 | " "$f" | sed 's/^| 截止日期 | \(.*\) |$/\1/')
    [ -z "${cur_title[$tid]}" ] && cur_title["$tid"]="(无标题)"
    [ -z "${cur_status[$tid]}" ] && cur_status["$tid"]="Unknown"
    [ -z "${cur_priority[$tid]}" ] && cur_priority["$tid"]="normal"
    [ -z "${cur_domain[$tid]}" ] && cur_domain["$tid"]="—"
    [ -z "${cur_due[$tid]}" ] && cur_due["$tid"]="—"
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

# --- Collect recently done (last 5) ---
done_list=""
done_count=0
if [ -d "$ARCHIVE_DIR" ]; then
  for f in "$ARCHIVE_DIR"/TASK-*.md; do
    [ -f "$f" ] || continue
    tid=$(basename "$f" .md)
    st=$(grep "^| 状态 | " "$f" | sed 's/^| 状态 | \(.*\) |$/\1/')
    if [ "$st" = "Done" ]; then
      t=$(grep "^# ${tid}: " "$f" | sed "s/^# ${tid}: //")
      upd=$(grep "^| 最后更新 | " "$f" | sed 's/^| 最后更新 | \(.*\) |$/\1/')
      done_list="${tid} ${t} | completed: ${upd}\n${done_list}"
      done_count=$((done_count + 1))
    fi
  done
fi
done_list=$(echo -e "$done_list" | head -5)

# --- Build report ---
echo "📋 KinemaTasks Daily Report — ${TODAY_DISPLAY}"
echo ""

# --- Diff section ---
if [ -n "$prev_snap" ]; then
  prev_display=$(TZ=Asia/Shanghai date -d "$prev_date" +"%-m/%-d" 2>/dev/null || echo "$prev_date")
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 昨日变动（${prev_display} → ${TODAY_DISPLAY}）"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # Parse previous snapshot task list
  declare -A prev_status prev_priority prev_domain prev_due
  in_snap=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^\|[[:space:]]TASK- ]]; then
      # Parse table row: | TASK-XXXXX | title | status | priority | domain | due |
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

  for tid in "${!cur_status[@]}"; do
    if [ -z "${prev_status[$tid]}" ]; then
      # New task
      new_tasks=" ${tid} ${cur_title[$tid]} | ${cur_priority[$tid]} | ${cur_domain[$tid]}\n${new_tasks}"
    else
      # Check status change
      if [ "${cur_status[$tid]}" != "${prev_status[$tid]}" ]; then
        status_changes=" ${tid} ${prev_status[$tid]} → ${cur_status[$tid]}\n${status_changes}"
      fi
      # Check field changes
      field_diff=""
      [ "${cur_priority[$tid]}" != "${prev_priority[$tid]}" ] && field_diff="${field_diff}优先级 ${prev_priority[$tid]} → ${cur_priority[$tid]}, "
      [ "${cur_domain[$tid]}" != "${prev_domain[$tid]}" ] && field_diff="${field_diff}领域 ${prev_domain[$tid]} → ${cur_domain[$tid]}, "
      [ "${cur_due[$tid]}" != "${prev_due[$tid]}" ] && field_diff="${field_diff}截止日期 ${prev_due[$tid]} → ${cur_due[$tid]}, "
      if [ -n "$field_diff" ]; then
        field_diff="${field_diff%, }"
        field_changes=" ${tid} ${field_diff}\n${field_changes}"
      fi
    fi
  done

  # Check for cancelled tasks (in prev snapshot, now cancelled in archived)
  for tid in "${!prev_status[@]}"; do
    if [ -z "${cur_status[$tid]}" ] && [ -n "${cancelled_tasks[$tid]}" ]; then
      cancel_changes=" ${tid}\n${cancel_changes}"
    fi
  done

  # Print diff
  has_diff=0
  if [ -n "$new_tasks" ]; then
    new_count=$(echo -e "$new_tasks" | wc -l)
    echo "🆕 新增 (${new_count})"
    echo -e "$new_tasks"
    echo ""
    has_diff=1
  fi
  if [ -n "$status_changes" ]; then
    sc_count=$(echo -e "$status_changes" | wc -l)
    echo "🔄 状态变更 (${sc_count})"
    echo -e "$status_changes"
    echo ""
    has_diff=1
  fi
  if [ -n "$field_changes" ]; then
    fc_count=$(echo -e "$field_changes" | wc -l)
    echo "📝 字段变更 (${fc_count})"
    echo -e "$field_changes"
    echo ""
    has_diff=1
  fi
  if [ -n "$cancel_changes" ]; then
    cc_count=$(echo -e "$cancel_changes" | wc -l)
    echo "🗑 取消 (${cc_count})"
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

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 当前任务状况"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Group current tasks
urgent_tasks=""
normal_tasks=""
low_tasks=""
snoozed_tasks=""
expired_tasks=""
in_progress=0
pending=0
snoozed_count=0
total=0

for tid in $(echo "${!cur_status[@]}" | tr ' ' '\n' | sort); do
  st="${cur_status[$tid]}"
  pr="${cur_priority[$tid]}"
  dm="${cur_domain[$tid]}"
  due="${cur_due[$tid]}"
  tt="${cur_title[$tid]}"

  total=$((total + 1))
  case "$st" in
    "In Progress") in_progress=$((in_progress + 1)) ;;
    "Pending") pending=$((pending + 1)) ;;
    "Snoozed") snoozed_count=$((snoozed_count + 1)) ;;
  esac

  entry=" [${st}] ${tid} ${tt}"

  # Due date formatting
  if [ "$due" != "—" ] && [ -n "$due" ]; then
    due_display=$(TZ=Asia/Shanghai date -d "$due" +"%-m-%-d" 2>/dev/null || echo "$due")
    entry="${entry} | due: ${due_display}"
    
    # Check expired
    if [ "$TODAY" \> "$due" ]; then
      days_overdue=$(( ($(date -d "$TODAY" +%s) - $(date -d "$due" +%s)) / 86400 ))
      overdue_warn=""
      [ "$days_overdue" -gt 7 ] && overdue_warn=" ⚠️"
      expired_tasks="${entry} | 超期 ${days_overdue}天${overdue_warn} | ${dm}\n${expired_tasks}"
      continue
    fi
  else
    entry="${entry} | —"
  fi
  entry="${entry} | ${dm}"

  case "$pr" in
    urgent) urgent_tasks="${entry}\n${urgent_tasks}" ;;
    normal) normal_tasks="${entry}\n${normal_tasks}" ;;
    low) low_tasks="${entry}\n${low_tasks}" ;;
  esac

  if [ "$st" = "Snoozed" ]; then
    snoozed_tasks="[Snoozed] ${tid} ${tt} | ${dm}\n${snoozed_tasks}"
  fi
done

# Print sections
if [ -n "$urgent_tasks" ]; then
  echo "🔴 Urgent"
  echo -e "$urgent_tasks"
  echo ""
fi
if [ -n "$normal_tasks" ]; then
  echo "🟡 Normal"
  echo -e "$normal_tasks"
  echo ""
fi
if [ -n "$low_tasks" ]; then
  echo "🟢 Low"
  echo -e "$low_tasks"
  echo ""
fi
if [ -n "$snoozed_tasks" ]; then
  echo "💤 Snoozed"
  echo -e "$snoozed_tasks"
  echo ""
fi
if [ -n "$expired_tasks" ]; then
  echo "⏰ 已过期"
  echo -e "$expired_tasks"
  echo ""
fi
if [ -n "$done_list" ]; then
  echo "✅ 最近完成"
  echo -e "$done_list"
  echo ""
fi

echo "共 ${total} 个活跃任务 | ${in_progress} In Progress · ${pending} Pending · ${snoozed_count} Snoozed"
