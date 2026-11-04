extends SceneTree

# Controlled common-rule/state fixtures. No rendered movement or human play is
# claimed here; HouseholdDay tests exercise its arrive/time/perform boundary.
var checks: int = 0
var failures: Array[String] = []
var history: FamilyHistory

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message);push_error(message)

func resident(id: String) -> Dictionary:
	var p: Dictionary = {"id":id,"age":7 if id=="rin" else 36,"at_home":true,"active_task":""}
	expect(history.attach(p,240),"The G1 authoring attaches to "+id)
	return p

func task(id: String, p: Dictionary, kind: String = "personal_project") -> Dictionary:
	var project: Dictionary = history.project_for(p)
	return {"id":id,"kind":kind,"activity":project.activity if kind=="personal_project" else kind,
		"project_id":project.id,"fixture":"rin_desk_chair" if int(p.age)<13 else "sofa","performed":0.0}

func context(at: float = 0) -> Dictionary:
	return {"elapsed":at,"adult_helpers":1,"other_deadline":false,"independent_child":false}

func authored_and_pure_choices() -> void:
	var p: Dictionary = resident("nagisa")
	expect(p.biography.episodes.size()==2 and p.biography.treasured_items[0].provenance=="authored_fiction","The past and important belongings carry authored provenance")
	expect(p.life_history.observed.is_empty() and p.life_history.experience_minutes.is_empty() and p.life_history.projects.seasonal_bread_plan.minutes==0,"An authored past creates no observed minutes, decisions or new progress")
	var before: Dictionary = p.duplicate(true)
	for ignored in 10:
		history.choice(p,"personal_project",context());history.choice(p,"cook",context());history.deadline_pressure(p,0)
	expect(FamilyHistory._same(p,before),"Repeated choice/pressure inspection changes no experience, project, promise or possession")
	var data: Dictionary = history.definitions.duplicate(true)
	data.profiles={"same_actor":data.profiles.nagisa.duplicate(true)}
	var common := FamilyHistory.new(data)
	var first: Dictionary = {"id":"same_actor"};common.attach(first,240)
	var second: Dictionary = first.duplicate(true);second.biography.values.creative_pride=0;second.biography.values.independence=0
	expect(float(common.choice(first,"personal_project",context()).score_delta)>float(common.choice(second,"personal_project",context()).score_delta),"The same actor and need context change choice from authored values, without a person-ID branch")

func shared_deadlines_and_independence() -> void:
	var parent: Dictionary = resident("ryo")
	var ordinary: float = float(history.choice(parent,"personal_project",context()).score_delta)
	expect(history.set_deadline(parent,"client_delivery",30),"A changed delivery deadline is an explicit scenario fact")
	expect(float(history.choice(parent,"personal_project",context()).score_delta)>ordinary+.3 and "締切" in history.choice(parent,"cook",context()).choice_reason,"A near deadline raises real draft work and gives the reason to request household help")
	var helper: Dictionary = resident("nagisa")
	var child: Dictionary = resident("rin")
	var cast: Dictionary = {"ryo":parent,"nagisa":helper,"rin":child}
	expect(history.context_for("nagisa",cast,{},0).other_deadline,"An explicitly shared client deadline can affect the adult partner's help")
	expect(not history.context_for("rin",cast,{},0).other_deadline,"An unannounced adult deadline is not read into the child's knowledge")
	var before: Dictionary = history.context_for("nagisa",cast,{},0)
	parent.biography.values.independence=0;parent.biography.experience.care=0
	expect(FamilyHistory._same(before,history.context_for("nagisa",cast,{},0)),"Other-person choice context ignores their private values and experience")
	var invited: float = float(history.choice(child,"family_time",context()).score_delta)
	child.biography.values.independence=0
	expect(float(history.choice(child,"family_time",context()).score_delta)>invited+.4,"With identical needs and invitation, wanting to try independently changes a child's acceptance priority")
	var watch: Dictionary = context();watch.independent_child=true
	expect(float(history.choice(helper,"care",watch).score_delta)<float(history.choice(helper,"care",context()).score_delta)-.3,"Visible actual independent work changes a parent's care proposal to giving space")

func actual_progress_and_completion() -> void:
	var p: Dictionary = resident("nagisa")
	var assigned: Dictionary = task("task_1",p)
	history.completed(p,assigned,0)
	expect(p.life_history.observed.is_empty() and p.life_history.projects.seasonal_bread_plan.artifact.is_empty(),"An assigned but unperformed task cannot claim experience or a finished plan")
	for i in 6:
		var actual: Dictionary = task("task_%d"%(i+1),p)
		actual.performed=15.0
		history.performed(p,actual,15,float((i+1)*15))
		var once: Dictionary = p.duplicate(true)
		history.performed(p,actual,15,float((i+1)*15))
		expect(FamilyHistory._same(once,p),"Repeating the same performed credit cannot double project or experience minutes")
		expect(p.life_history.projects.seasonal_bread_plan.artifact.is_empty(),"Progress alone does not publish a completion before finish")
		history.completed(p,actual,float((i+1)*15))
		var finished: Dictionary = p.duplicate(true)
		history.completed(p,actual,float((i+1)*15))
		expect(FamilyHistory._same(finished,p),"The same completed task records once")
	var progress: Dictionary = p.life_history.projects.seasonal_bread_plan
	expect(progress.completed and progress.minutes==90 and progress.artifact.owner==p.id and progress.artifact.kind=="recipe_plan","Only ninety actual project minutes plus finish create this owner's recipe plan")
	expect(p.life_history.tools_out and p.life_history.experience_minutes.bread_notebook==90,"Actually used tools remain out and practice is counted by the actual activity")
	var clean: Dictionary = task("task_7",p,"tidy_tools");clean.performed=5
	history.performed(p,clean,5,95);history.completed(p,clean,95)
	expect(not p.life_history.tools_out and progress.fixture=="parents_storage" and progress.artifact.fixture=="parents_storage","Only performed tidying stores the existing source and completed artifact")
	expect(history.valid_person(p,95),"The complete valid current state passes the save boundary")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(p))
	expect(history.valid_person(saved,95) and FamilyHistory._same(saved,p),"JSON preserves authored/observed separation, identities, progress and deadlines")
	for field in ["projects","deadlines","credited_tasks"]:
		var bad: Dictionary = p.duplicate(true);bad.life_history[field]=[]
		expect(not history.valid_person(bad,95),"Malformed "+field+" is rejected before nested access")
	var bad: Dictionary = p.duplicate(true);bad.life_history.projects.seasonal_bread_plan.minutes=INF
	expect(not history.valid_person(bad,95),"Nonfinite project credit is rejected")
	bad=p.duplicate(true);bad.life_history.projects.seasonal_bread_plan.artifact.owner="other"
	expect(not history.valid_person(bad,95),"An artifact cannot be reassigned by a corrupted save")
	bad=p.duplicate(true);bad.erase("life_history")
	expect(not history.valid_person(bad,95),"Missing new state is rejected rather than silently inventing a life history")

func actual_decline_is_not_shared_time() -> void:
	var child: Dictionary = resident("rin")
	var own: Dictionary = task("task_1",child)
	history.declined(child,"parent_task",own,0)
	var once: Dictionary = child.duplicate(true)
	history.declined(child,"parent_task",own,0)
	expect(FamilyHistory._same(once,child) and child.life_history.observed.size()==1,"An actual invitation refusal records one decision, even when called twice")
	expect(child.life_history.experience_minutes.is_empty() and child.life_history.observed[0].actual_minutes==0 and child.life_history.observed[0].status=="declined_family_invitation","Declining grants no shared care, practice or completed object")

func run() -> void:
	history=FamilyHistory.new()
	authored_and_pure_choices();shared_deadlines_and_independence();actual_progress_and_completion();actual_decline_is_not_shared_time()
	print("Family history checks: %d passed, %d failed"%[checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
