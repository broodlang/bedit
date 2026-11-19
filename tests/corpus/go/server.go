package main
// ^^^^ keyword

import (
	"fmt"
	// ^^ string
	"strings"
)

// Point is a point.
// ^^^^^^^^^^^^^^^^^ comment
type Point struct {
	//  ^^^^^ special
	X int
	Y float64
}

func (p Point) Describe(name string) string {
	//            ^^^^^^^^ definition
	switch name {
	case "x":
		return fmt.Sprintf("%d", p.X)
		//         ^^^^^^^ function
	default:
		return strings.Repeat(`raw`, 3)
		//                    ^^^^^ string
		//                           ^ number
	}
}

func main() {
	points := []Point{
		{X: 1, Y: 2.5},
		//        ^^^ number
	}
	for _, p := range points {
		//         ^^^^^ keyword
		if p.X > 0 {
			fmt.Println(p.Describe("x"), nil)
			//                           ^^^ constant
		}
	}
}
