// the greeter
// ^^^^^^^^^^^ comment
using System;
// ^^ keyword

namespace App
{
    [Serializable]
    // ^^^^^^^^^^ special
    public class Greeter<T> : IGreeter
    // ^^^ keyword            ^^^^^^^^ special
    //           ^^^^^^^ special
    {
        private readonly string name = "x";
        //               ^^^^^^ special
        //                             ^^^ string

        public async Task<string> Greet(int n)
        //           ^^^^ special ^^^^^ definition
        {
            var s = $"hi {name}";
            //        ^^^ string
            //           ^ special
            switch (n)
            {
                case 1:
                    return @"one";
                    //     ^^^^^^ string
                default:
                    break;
            }
            Console.WriteLine('c', 1.5m, null, true);
            // ^^^^ plain     ^^^ string ^^^^ constant
            //      ^^^^^^^^^ function
            //                     ^^^^ number
            return s;
        }
    }
}
