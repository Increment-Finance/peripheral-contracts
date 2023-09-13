import { bufferToHex, keccak256, toBuffer } from "ethereumjs-util";

export default class MerkleTree {
  private readonly elements: Buffer[];
  private readonly bufferElementPositionIndex: { [hexElement: string]: number };
  private readonly layers: Buffer[][];
  private readonly emptyBytes: Buffer;

  constructor(elements: Buffer[]) {
    this.elements = [...elements];
    // Sort elements
    //this.elements.sort(Buffer.compare) !!!!! MURKY::: WE ASSUME ELEMENTS ARE PRE-SORTED BY USER
    // Deduplicate elements
    //this.elements = MerkleTree.bufDedup(this.elements) !!!!! MURKY::: GENERIC TREE
    this.emptyBytes = toBuffer(
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    );
    this.bufferElementPositionIndex = this.elements.reduce<{
      [hexElement: string]: number;
    }>((memo, el, index) => {
      memo[bufferToHex(el)] = index;
      return memo;
    }, {});

    // Create layers
    this.layers = this.getLayers(this.elements);
  }

  getLayers(elements: Buffer[]): Buffer[][] {
    if (elements.length === 0) {
      throw new Error("empty tree");
    }

    const layers = [];
    layers.push(elements);

    // Get next layer until we reach the root
    while (layers[layers.length - 1].length > 1) {
      layers.push(this.getNextLayer(layers[layers.length - 1]));
    }

    return layers;
  }

  getNextLayer(elements: Buffer[]): Buffer[] {
    return elements.reduce<Buffer[]>((layer, el, idx, arr) => {
      if (idx % 2 === 0) {
        // Hash the current element with its pair element
        layer.push(MerkleTree.combinedHash(el, arr[idx + 1]));
      }

      return layer;
    }, []);
  }

  static combinedHash(first: Buffer, second: Buffer): Buffer {
    if (!first) {
      first = toBuffer(
        "0x0000000000000000000000000000000000000000000000000000000000000000"
      ); //!!!!! MURKY::: ALWAYS NEED TO HASH EACH LAYER
    }
    if (!second) {
      second = toBuffer(
        "0x0000000000000000000000000000000000000000000000000000000000000000"
      ); //!!!!! MURKY::: ALWAYS NEED TO HASH EACH LAYER
    }

    return keccak256(MerkleTree.sortAndConcat(first, second));
  }

  getRoot(): Buffer {
    return this.layers[this.layers.length - 1][0];
  }

  getHexRoot(): string {
    return bufferToHex(this.getRoot());
  }

  hashLevel(elements: Buffer[]): Buffer[] {
    let result: Buffer[] = [];

    let length = elements.length;
    if (length % 2 === 1) {
      result = Array.from(
        { length: Math.floor(length / 2) + 1 },
        () => this.emptyBytes
      );
      result[result.length - 1] = MerkleTree.combinedHash(
        elements[length - 1],
        this.emptyBytes
      );
    } else {
      result = Array.from(
        { length: Math.floor(length / 2) },
        () => this.emptyBytes
      );
    }

    let pos = 0;
    for (let i = 0; i < length - 1; i += 2) {
      result[pos] = MerkleTree.combinedHash(elements[i], elements[i + 1]);
      ++pos;
    }
    return result;
  }

  getProof(el: Buffer) {
    let idx = this.bufferElementPositionIndex[bufferToHex(el)];

    if (typeof idx !== "number") {
      throw new Error("Element does not exist in Merkle tree");
    }

    let result: Buffer[] = [];
    let data = this.elements;

    let pos = 0;
    while (data.length > 1) {
      if (idx % 2 === 1) {
        result[pos] = data[idx - 1];
      } else if (idx + 1 === data.length) {
        result[pos] = this.emptyBytes;
      } else {
        result[pos] = data[idx + 1];
      }
      ++pos;
      idx = Math.floor(idx / 2);

      data = this.hashLevel(data);
    }

    return result;
  }

  getHexProof(el: Buffer): string[] {
    const proof = this.getProof(el);

    return MerkleTree.bufArrToHexArr(proof);
  }

  private static bufDedup(elements: Buffer[]): Buffer[] {
    return elements.filter((el, idx) => {
      return idx === 0 || !elements[idx - 1].equals(el);
    });
  }

  private static bufArrToHexArr(arr: Buffer[]): string[] {
    if (arr.some((el) => !Buffer.isBuffer(el))) {
      throw new Error("Array is not an array of buffers");
    }

    return arr.map((el) => "0x" + el.toString("hex"));
  }

  public static sortAndConcat(...args: Buffer[]): Buffer {
    return Buffer.concat([...args].sort(Buffer.compare));
  }
}
