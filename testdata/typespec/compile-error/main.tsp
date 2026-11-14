import "@typespec/http";

using Http;

@service(#{ title: "Sample" })
namespace Sample;

model Item {
  id: string;
  name: Missing;
}

@route("/items")
interface Items {
  @get list(): Item[];
}
