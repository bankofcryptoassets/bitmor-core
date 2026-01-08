import BigNumber from "bignumber.js";

function almostEqualAssertion(this: any, expected: any, actual: any, message: string): any {
  this.assert(
    expected.plus(new BigNumber(1)).eq(actual) ||
      expected.plus(new BigNumber(2)).eq(actual) ||
      actual.plus(new BigNumber(1)).eq(expected) ||
      actual.plus(new BigNumber(2)).eq(expected) ||
      expected.eq(actual),
    `${message} expected #{act} to be almost equal #{exp}`,
    `${message} expected #{act} to be different from #{exp}`,
    expected.toString(),
    actual.toString()
  );
}

export function almostEqual() {
  return function (chai: any, utils: any) {
    chai.Assertion.addMethod('almostEqual', function (this: any, value: any, message: string) {
      var expected = new BigNumber(value);
      var actual = new BigNumber(this._obj);
      almostEqualAssertion.apply(this, [expected, actual, message]);
    });

    chai.Assertion.addMethod('greaterThan', function (this: any, value: any, message: string) {
      var expected = new BigNumber(value);
      var actual = new BigNumber(this._obj);
      this.assert(
        actual.gt(expected),
        `${message} expected #{act} to be greater than #{exp}`,
        `${message} expected #{act} to not be greater than #{exp}`,
        expected.toString(),
        actual.toString()
      );
    });

    chai.Assertion.addMethod('greaterThanOrEqual', function (this: any, value: any, message: string) {
      var expected = new BigNumber(value);
      var actual = new BigNumber(this._obj);
      this.assert(
        actual.gte(expected),
        `${message} expected #{act} to be greater than or equal #{exp}`,
        `${message} expected #{act} to not be greater than or equal #{exp}`,
        expected.toString(),
        actual.toString()
      );
    });

    chai.Assertion.addMethod('lessThan', function (this: any, value: any, message: string) {
      var expected = new BigNumber(value);
      var actual = new BigNumber(this._obj);
      this.assert(
        actual.lt(expected),
        `${message} expected #{act} to be less than #{exp}`,
        `${message} expected #{act} to not be less than #{exp}`,
        expected.toString(),
        actual.toString()
      );
    });
  };
}
