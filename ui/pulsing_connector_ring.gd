extends Polygon2D

var base_color: Color
var bright_color: Color
var pulse_offset: float
var pulse_phase: float = 0.0

func _ready():
	set_process(true)

func setup(colors: Dictionary, offset: float):
	base_color = colors.base
	bright_color = colors.bright
	pulse_offset = offset
	color = base_color

func _process(delta):
	pulse_phase += delta * 3.0
	var pulse_value = (sin(pulse_phase + pulse_offset) + 1.0) / 2.0
	color = base_color.lerp(bright_color, pulse_value)
