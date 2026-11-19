<!DOCTYPE html>
<p class="lead">Hello</p>
<?php
// ^^ special
// the greeter
// ^^^^^^^^^^^ comment
declare(strict_types=1);

namespace App\Greet;
//        ^^^^^^^^^ special

use App\Base;

/** A greeter. */
// ^^^^^^^^^^^^^^ comment
#[Service]
// ^^^^^^ special
final class Greeter extends Base implements Runnable
// ^^ keyword               ^^^^ special    ^^^^^^^^ special
//          ^^^^^^^ special
{
    public const MAX = 0x10;
    //           ^^^ constant
    //                 ^^^^ number
    private string $name;
    //      ^^^^^^ special

    public function __construct(string $name)
    //              ^^^^^^^^^^^ definition
    {
        $this->name = $name;
    }

    public function run(): void
    //              ^^^ definition
    {
        $names = ['a', 'b'];
        // ^^^ plain
        //        ^^^ string
        foreach ($names as $each) {
            if ($each === '') {
                continue;
            } elseif ($each === 'b') {
                echo strtoupper("hi {$each} and $this->name");
                //   ^^^^^^^^^^ function   ^^^^^ string
                //               ^^^ string
                //                   ^^^^^ plain
            } else {
                $this->greet($each, 1.5, true);
                //     ^^^^^ function    ^^^^ constant
                //                  ^^^ number
            }
        }
        switch (count($names)) {
            case 0:
                break;
            default:
                array_map(function ($item) {
                    return $item;
                }, $names);
        }
        $kind = match ($names[0]) {
            'x' => 1,
            default => 2,
        };
        $block = <<<EOT
            heredoc text
            EOT;
        $nothing = null;
        //         ^^^^ constant
        try {
            self::work([1, 2]);
            //    ^^^^ function
        } catch (RuntimeException $e) {
            //   ^^^^^^^^^^^^^^^^ special
            throw $e;
        } finally {
            parent::close();
        }
    }

    private static function greet(string $who, float $weight, bool $loud): string
    {
        return 'hello ' . $who;
    }
}

interface Shape
//        ^^^^^ special
{
    public function area(): float;
    //              ^^^^ definition
}

trait Loud
//    ^^^^ special
{
}

enum Color: string
{
    case Red = 'r';
    //   ^^^ constant
}

function shout(string $text): string
//       ^^^^^ definition
{
    return strtoupper($text);
}
?>
<footer></footer>
