// Optional bonus behavior: when true, manual end date updates duration.
const TASK_ENABLE_BIDIRECTIONAL_SYNC = true;

function task_parse_datetime(value) {
    return value ? frappe.datetime.str_to_obj(value) : null;
}

function task_is_empty(value) {
    return value === undefined || value === null || value === "";
}

function task_get_date_only(dateObj) {
    return new Date(dateObj.getFullYear(), dateObj.getMonth(), dateObj.getDate());
}

function task_toggle_duration_required(frm) {
    frm.toggle_reqd("duration", !!frm.doc.exp_start_date);
}

async function task_set_value_if_changed(frm, fieldname, value) {
    const currentValue = frm.doc[fieldname];

    if (fieldname === "duration") {
        if (task_is_empty(currentValue) && task_is_empty(value)) return;

        if (!task_is_empty(currentValue) && !task_is_empty(value) && cint(currentValue) === cint(value)) {
            return;
        }
    } else if (currentValue === value) {
        return;
    }

    // Prevent recursive handlers when we update fields programmatically.
    frm.__task_dates_internal_update = true;
    try {
        await frm.set_value(fieldname, value);
    } finally {
        frm.__task_dates_internal_update = false;
    }
}

async function task_recalculate_expected_end_date(frm, showDurationError) {
    if (!frm.doc.exp_start_date || task_is_empty(frm.doc.duration)) return;

    const durationDays = cint(frm.doc.duration);
    if (durationDays <= 0) {
        if (showDurationError) {
            frappe.msgprint("Duration (Days) must be greater than 0.");
            await task_set_value_if_changed(frm, "duration", null);
        }

        await task_set_value_if_changed(frm, "exp_end_date", null);
        return;
    }

    const startRaw = frm.doc.exp_start_date;
    const startObj = task_parse_datetime(startRaw);
    if (!startObj) return;

    // Calendar-day calculation from task requirements: duration - 1.
    const endObj = new Date(startObj.getTime());
    endObj.setDate(endObj.getDate() + durationDays - 1);

    const datePart = frappe.datetime.obj_to_str(endObj);
    let timePart = "00:00:00";

    if (startRaw.indexOf(" ") !== -1) {
        const split = startRaw.split(" ");
        if (split.length > 1 && split[1]) {
            timePart = split[1];
        }
    }

    await task_set_value_if_changed(frm, "exp_end_date", datePart + " " + timePart);
}

async function task_recalculate_duration_from_expected_end_date(frm) {
    if (!frm.doc.exp_start_date || !frm.doc.exp_end_date) return;

    const startObj = task_parse_datetime(frm.doc.exp_start_date);
    const endObj = task_parse_datetime(frm.doc.exp_end_date);
    if (!startObj || !endObj) return;

    const startDateOnly = frappe.datetime.obj_to_str(task_get_date_only(startObj));
    const endDateOnly = frappe.datetime.obj_to_str(task_get_date_only(endObj));
    // Inverse calculation for optional bidirectional sync.
    const dayDiff = cint(frappe.datetime.get_day_diff(endDateOnly, startDateOnly));
    const durationDays = dayDiff + 1;

    if (durationDays <= 0) {
        await task_set_value_if_changed(frm, "duration", null);
        return;
    }

    await task_set_value_if_changed(frm, "duration", durationDays);
}

async function task_validate_date_order(frm) {
    if (!frm.doc.exp_start_date || !frm.doc.exp_end_date) return true;

    const startObj = task_parse_datetime(frm.doc.exp_start_date);
    const endObj = task_parse_datetime(frm.doc.exp_end_date);
    if (!startObj || !endObj) return true;

    const startDateOnly = task_get_date_only(startObj);
    const endDateOnly = task_get_date_only(endObj);
    if (endDateOnly < startDateOnly) {
        frappe.msgprint("Expected End Date cannot be earlier than Expected Start Date.");
        await task_set_value_if_changed(frm, "exp_end_date", null);
        return false;
    }

    return true;
}

frappe.ui.form.on("Task", {
    refresh(frm) {
        task_toggle_duration_required(frm);
    },

    async exp_start_date(frm) {
        if (frm.__task_dates_internal_update) return;

        task_toggle_duration_required(frm);

        if (!task_is_empty(frm.doc.duration)) {
            await task_recalculate_expected_end_date(frm, false);
        } else if (TASK_ENABLE_BIDIRECTIONAL_SYNC) {
            await task_recalculate_duration_from_expected_end_date(frm);
        }

        await task_validate_date_order(frm);
    },

    async duration(frm) {
        if (frm.__task_dates_internal_update) return;

        await task_recalculate_expected_end_date(frm, true);
        await task_validate_date_order(frm);
    },

    async exp_end_date(frm) {
        if (frm.__task_dates_internal_update) return;

        const isValid = await task_validate_date_order(frm);
        if (!isValid) return;

        if (TASK_ENABLE_BIDIRECTIONAL_SYNC) {
            await task_recalculate_duration_from_expected_end_date(frm);
        }
    },

    async validate(frm) {
        if (frm.__task_dates_internal_update) return;

        task_toggle_duration_required(frm);

        if (!task_is_empty(frm.doc.duration)) {
            await task_recalculate_expected_end_date(frm, false);
        } else if (TASK_ENABLE_BIDIRECTIONAL_SYNC) {
            await task_recalculate_duration_from_expected_end_date(frm);
        }

        await task_validate_date_order(frm);
    }
});
