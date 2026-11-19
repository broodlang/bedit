module example.com/app
// ^^^ keyword
//     ^^^^^^^^^^^^^^^ string

go 1.22
// ^^^^ number

// deps
// ^^^^ comment
require (
	github.com/a/b v1.2.3 // indirect
	//             ^^^^^^ number
)

replace github.com/a/b => ../b
//                     ^^ special
//                        ^^^^ string
