class Worker:
    # ^^^^^^ special
    def __init__(self, n):
        # ^^^^^^ definition
        self.n = n  # a note
        #           ^^^^^^^^ comment

    def run(self, xs):
        total = 0
        for x in xs:
            if x > 0:
                #  ^ number
                total += x
            else:
                total -= 1
        return "done"
        #      ^^^^^^ string
