interface Props {
  // ^^^^ keyword
  title: string;
  //     ^^^^^^ special
}

export function App(props: Props) {
  //            ^^^ definition
  return (
    // ^ keyword
    <div className="app">
      <span>{props.title}</span>
    </div>
  );
}
