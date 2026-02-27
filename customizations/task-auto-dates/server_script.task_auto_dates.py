if doc.exp_start_date and doc.duration:
    duration_days = int(doc.duration)

    if duration_days <= 0:
        frappe.throw("Duration (Days) must be greater than 0.")

    # Server-side duplicate of client calculation (single source of truth for data integrity).
    doc.exp_end_date = frappe.utils.add_to_date(
        doc.exp_start_date,
        days=duration_days - 1,
        as_string=True,
        as_datetime=True,
    )

if doc.exp_start_date and doc.exp_end_date:
    start_date = frappe.utils.getdate(doc.exp_start_date)
    end_date = frappe.utils.getdate(doc.exp_end_date)

    if end_date < start_date:
        frappe.throw("Expected End Date cannot be earlier than Expected Start Date.")

if doc.exp_end_date and doc.status not in ("Completed", "Cancelled"):
    # Block saving overdue tasks unless they are already finished/cancelled.
    end_date = frappe.utils.getdate(doc.exp_end_date)
    current_date = frappe.utils.getdate(frappe.utils.nowdate())

    if end_date < current_date:
        frappe.throw(
            "\u0414\u0430\u0442\u0430 \u0437\u0430\u0432\u0435\u0440\u0448\u0435\u043d\u0438\u044f "
            "\u0437\u0430\u0434\u0430\u0447\u0438 \u0443\u0436\u0435 \u043f\u0440\u043e\u0448\u043b\u0430! "
            "\u0418\u0437\u043c\u0435\u043d\u0438\u0442\u0435 \u0434\u0430\u0442\u0443 \u0438\u043b\u0438 "
            "\u0441\u0442\u0430\u0442\u0443\u0441 \u0437\u0430\u0434\u0430\u0447\u0438."
        )
