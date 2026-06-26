## PlotOption : Resource
## A single choice option in a select node.
class_name PlotOption extends Resource

@export var ZH: String = ""
@export var EN: String = ""
@export var target_node: int = -1
@export var target_plot_id: String = ""
@export var target_node_index: int = -1

## When true, loop back to the select node after reaction nodes finish,
## letting the player re-choose.  Set by _rechoose target or @rechoose command.
@export var rechoose: bool = false

## Immediate reaction nodes played when this option is selected.
## Inserted right after the select node, before the main plot resumes.
## Empty array = no reaction (jump or continue directly).
@export var reaction_nodes: Array[PlotNode] = []
