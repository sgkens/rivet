# Rivet Task Tracker

> [!NOTE]
> Use the Rivet interactive menu (`./rivet.ps1 menu`) or CLI (`./rivet.ps1 work-items`) to list, pull, push, or scaffold work items. Individual work item specifications reside under `.rivet/work-items/*.md`.

> [!CAUTION]
> Content between the `<!--rivet: generated Tasklist-->` markers is generated and synchronized automatically from local work items and GitLab issues. Follow the structured Markdown block format if modifying manually.

## **Tasklist**

<!--rivet: generated Tasklist-->

### 🎯 **{{TITLE}}**

> _**Task Meta:**_ [#{{IID}}]({{IID_LINK}}) &nbsp;|&nbsp; _**Last Updated:**_ `{{UPDATE_DATE}}` \
> _**Assigned to:**_ {{`@assignee1`, `@assignee2`}} {{START_DATE | END_DATE}} \
> _**Labels:**_ {{`feature`, `ui`, `tui`}} \
> _**Status:**_ {{🟢 open | ✅ closed}}

{{SUMMARY_OR_DESCRIPTION}}

#### **LAST MOST RECENT COMMENT**

> > **@{{COMMENT_AUTHOR}}** _({{COMMENT_DATE}})_: \
> > {{COMMENT_BODY}}
> >
> > > **@{{SUBCOMMENT_AUTHOR}}**: {{SUBCOMMENT_BODY}}

<!--rivet: generated Tasklist-->

