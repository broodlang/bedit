// the widget
// ^^^^^^^^^^ comment
#include <vector>
// ^^^^^ keyword

namespace app {
// ^^^^^^ keyword

class Widget : public Base {
//    ^^^^^^ special  ^^^^ special
public:
    auto size() const -> int;
    // ^ special
    //   ^^^^ definition
    ~Widget();
    // ^^^^ definition

private:
    int count_ = 0;
};

template <typename T>
// ^^^^^ keyword
void Widget::run(int n,
                 T t) {
    switch (n) {
    case 1:
        std::sort(v.begin(), v.end());
        // <- special
        //   ^^^^ function
        //          ^^^^^ function
        break;
    }
    auto s = R"(raw)";
    //       ^^^^^^^^ string
    this->get<int>(nullptr, true, 1.5);
    // ^ keyword   ^^^^^^^ constant
    //    ^^^ function      ^^^^ constant
    //                            ^^^ number
}

} // namespace app
