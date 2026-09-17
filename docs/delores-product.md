# Delores — Product Intent and North Star

## Why Delores exists

Delores began from a simple observation:

Two lightweight macOS tools solved different parts of the same interaction problem.

The original selection toolbar was good at acting on something the user had already
selected. It appeared at the top of the screen, offered a few immediate actions, returned
the result close to where the interaction began, and disappeared when it was no longer
needed.

Tinycast was good at the opposite situation: the user had an intention, but had not yet
provided the object. A global shortcut opened a lightweight command surface for search,
commands, AI conversations and other explicit tasks.

Their interaction languages were already similar:

- native macOS;
- lightweight and transient;
- keyboard and pointer first;
- small surfaces instead of full application windows;
- available when needed and quiet when not needed.

Delores exists to combine those ideas into one product rather than keep them as two
separate utilities.

It is not a port of one application into another.

It is a new product built from the strongest interaction ideas of both.

---

## Product statement

**Delores is a lightweight native macOS command layer that chooses the smallest useful
interaction form for the user's current intent.**

The user should not have to decide which Delores mode to open.

Their current context should make that choice obvious.

```text
I already selected something
        ↓
Context Surface

I want to start or find something
        ↓
Command Surface

I want Delores close at hand
        ↓
Companion Surface
````

Behind those forms is one shared capability core.

```text
                    Delores Core
                         │
        ┌────────────────┼────────────────┐
        │                │                │
     Actions           Search          Window
     AI / Models       Clipboard       Placement
     Text Injection    Settings        ...
        │                │                │
        └────────────────┼────────────────┘
                         │
             ┌───────────┼───────────┐
             ↓           ↓           ↓
          Context     Companion    Command
```

**One product. One core. Three forms. Many capabilities.**

---

## The three forms

### Context Surface

The Context Surface appears because the user has already supplied the object.

Today that primarily means selected text.

Its job is to offer the smallest useful set of actions for that context:

* Translate
* Explain
* Summarize
* Search
* future context-appropriate actions

The interaction should remain local and lightweight:

```text
select
→ choose an action
→ read or use the result
→ continue working
```

A result may support small local continuation such as copy, replace, retry or a short
follow-up.

The Context Surface must not gradually become a second full Chat application.

When a task becomes conversational, tool-heavy, exploratory or otherwise complex,
Delores may hand the task to the Command Surface while preserving the context already
provided by the user.

---

### Command Surface

The Command Surface appears because the user explicitly summons Delores.

Its natural entry is a global shortcut.

It is the most complete form of Delores and owns the long tail of deliberate tasks:

* search;
* commands;
* application launching;
* AI conversations;
* model switching;
* tools;
* settings;
* tasks that require more room or more interaction.

It should inherit the mature Tinycast command experience rather than be rebuilt merely
to look different.

The Command Surface is the place a task can grow into.

It should not be forced upon the user for a task that can be completed comfortably in
the Context Surface.

---

### Companion Surface

The Companion exists so Delores can be found without first being summoned.

It is an ambient presence, not another workspace.

Its responsibilities are deliberately small:

* be visible without demanding attention;
* acknowledge useful context;
* recall the most recent context;
* hand the user to the Context or Command Surface;
* provide very lightweight ambient feedback.

The Companion must not become:

* another chat client;
* another Action catalogue;
* another model configuration surface;
* another history system;
* another independent AI runtime.

The Companion helps the user reach Delores.

It does not become a fourth way to rebuild Delores.

---

## Capabilities are not forms

A capability is something Delores can do.

Examples include:

* Translate;
* Explain;
* Summarize;
* Search;
* AI generation;
* Clipboard;
* Text Injection;
* Window Snapping;
* Split Divider;
* Window Placement.

Capabilities belong to the shared core.

Surfaces only decide:

1. when a capability is appropriate;
2. how the user invokes it;
3. how its progress and result are presented.

Window snapping and the split divider therefore are not additional Delores surfaces.

They are capabilities that briefly expose an affordance while the user is already
performing a window gesture.

---

## One Action, multiple entry points

An Action is identified by what it does, not by where its button appears.

```text
                    Translate
                        │
             shared action identity
                        │
        ┌───────────────┼───────────────┐
        ↓               ↓               ↓
     Context         Companion        Command
    if useful        if useful        if useful
```

The same Action may be exposed by several forms.

Those forms may present its result differently, but they must not silently redefine what
the Action means.

A user should be able to configure an Action once and reasonably expect that choice to
follow the Action across Delores.

Surface-specific presentation is good.

Surface-specific duplicate capability implementations are not.

---

## Context first, Surface second

Delores should first understand what the user has already provided.

Only then should it decide what interface to show.

Examples:

```text
selected text + Translate
→ Context result

selected text + short follow-up
→ remain in Context

selected text + sustained conversation / tools / model exploration
→ continue in Command with the selection preserved

global shortcut + "translate..."
→ Command

window drag near a snap target
→ window-placement affordance
```

The user should never have to repeat information Delores has already captured merely
because the task crossed from one Surface to another.

**Context first. Surface second. Capability shared.**

---

## Lightweight is a product property

"Lightweight" does not mean Delores must have few capabilities.

It means the product reveals only the amount of interface necessary for the task.

The ideal Delores experience is often:

```text
nothing
→ a small surface appears
→ one task is completed
→ nothing again
```

Lightweight therefore means:

* no unnecessary application window;
* no large Surface for a small task;
* no duplicated configuration;
* no repeated questions for context already supplied;
* no permanent UI where a transient affordance is sufficient;
* minimal idle CPU and memory cost;
* disabled capabilities should install no unnecessary monitors, polling or timers;
* surfaces disappear cleanly when their job is done.

Capability can grow.

Interaction weight should not grow with it unless the task actually requires it.

---

## Surface escalation

Surfaces form a natural increase in interaction depth:

```text
No Surface
    ↓
Context
    ↓
Command
```

Companion sits beside this hierarchy as an ambient entry point.

Escalation should happen because the task became more complex, not because implementation
is easier in a larger Surface.

Examples of valid escalation:

* a quick explanation becomes a long conversation;
* the user wants to change models while exploring an answer;
* tools or web search become necessary;
* the task requires history, attachments or several turns.

Examples that should normally remain in Context:

* translate;
* summarize;
* explain;
* copy;
* replace;
* retry;
* a small follow-up directly related to the current result.

**Use the smallest sufficient Surface.**

---

## Gesture ownership

Multiple Delores capabilities may be enabled at the same time.

For example:

```text
Companion   ON
Window Snap ON
Divider     ON
Context     ON
```

They should not need to disable one another merely because they observe similar input.

Instead:

> one physical gesture belongs to exactly one consumer.

Delores should arbitrate the gesture, not disable unrelated product capabilities.

---

## Product boundaries

Delores is not:

* Tinycast with extra buttons;
* the old selection toolbar embedded unchanged inside Tinycast;
* three separate utilities sharing an icon;
* a Chat interface placed everywhere;
* a collection of duplicated AI pipelines;
* a reason to rewrite mature Tinycast capabilities merely to rename them;
* a reason to import the old Huaci managers, configuration system, AI service,
  clipboard stack or application lifecycle wholesale.

Tinycast provides a mature foundation.

Huaci provides proven interaction ideas and behaviour.

Delores is the product created by integrating them around one coherent interaction
model.

---

## Product decision test

Before adding or changing a feature, answer these questions:

1. What is the user's intent?
2. What context has the user already provided?
3. What capability actually performs the task?
4. What is the smallest sufficient Surface?
5. Does another Delores Surface already use the same capability?
6. Are we sharing that capability, or accidentally creating another implementation?
7. Does the change make the user repeat information?
8. Are we making a Surface larger because the task requires it, or because implementation
   is easier there?
9. Does this preserve the quiet, transient character of Delores?

If the implementation is simpler only by changing the answer to one of these product
questions, stop and treat it as a product decision rather than an implementation detail.

---

## North star

The finished product should feel less like launching software and more like macOS gaining
a useful layer of intent.

When reading:

```text
select text
→ Delores appears at the top
→ act
→ continue reading
```

When starting something:

```text
press the shortcut
→ Delores appears
→ search, command or talk
→ continue working
```

When no explicit summon is desirable:

```text
the Companion is nearby
→ recall or hand off
→ Delores appears in the form the task needs
```

When arranging windows:

```text
drag
→ the relevant placement affordance appears
→ release
→ it disappears
```

The user may see several forms over the course of a day.

They should never feel like they used several products.

**That is Delores.**
