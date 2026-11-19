// Synthetic opening balances and same-day activity for the QA dashboard.
const products = [
  { name: 'باراسيتامول 500 ملغ', reorder: 8 },
  { name: 'محلول ملحي 0.9٪', reorder: 5 },
  { name: 'ضماد معقم', reorder: 10 },
];

export const demoBranches = [
  { id: 'hader', name: 'فرع الحاضر', staff: 'موظف 01', cash: 200000, counted: 254000, debts: [73000, 85], stock: [6, 18, 22], countedStock: [6, 17, 22], sales: [48000, 27000, 16000], purchases: [21000], credit: 16000 },
  { id: 'aleppo', name: 'فرع حلب', staff: 'موظف 02', cash: 300000, counted: 405000, debts: [115000, 160], stock: [27, 3, 34], countedStock: [27, 3, 34], sales: [61000, 44000, 19000], purchases: [19000], credit: 0 },
  { id: 'safira', name: 'فرع السفيرة', staff: 'موظف 03', cash: 150000, counted: null, debts: [42000, 45], stock: [18, 12, 8], countedStock: [null, null, null], sales: [33000, 23000], purchases: [12000], credit: 23000 },
  { id: 'zarbeh', name: 'فرع الزربة', staff: 'موظف 04', cash: 120000, counted: 151000, debts: [35000, 0], stock: [4, 0, 16], countedStock: [4, 0, 16], sales: [29000, 17000], purchases: [15000], credit: 0 },
  { id: 'atereb', name: 'فرع الأتارب', staff: 'موظف 05', cash: 180000, counted: 222000, debts: [62000, 72], stock: [21, 10, 28], countedStock: [21, 10, 28], sales: [39000, 26000, 18000], purchases: [22000], credit: 18000 },
].map(branch => {
  const inventory = products.map((product, index) => ({
    ...product,
    quantity: branch.stock[index],
    counted: branch.countedStock[index],
  }));
  const sales = branch.sales.map((value, index) => ({
    id: `S-${String(index + 1).padStart(2, '0')}`,
    type: 'بيع',
    value,
    cash: index === branch.sales.length - 1 ? value - branch.credit : value,
  }));
  const purchases = branch.purchases.map((value, index) => ({
    id: `P-${String(index + 1).padStart(2, '0')}`,
    type: 'شراء',
    value,
    cash: -value,
  }));
  const activity = [...sales, ...purchases];
  const expected = branch.cash + activity.reduce((total, entry) => total + entry.cash, 0);

  return {
    id: branch.id,
    name: branch.name,
    staff: branch.staff,
    debts: { customersSyp: branch.credit, suppliersSyp: branch.debts[0], suppliersUsd: branch.debts[1] },
    activity,
    inventory,
    sales: sales.reduce((total, entry) => total + entry.value, 0),
    invoiceCount: sales.length,
    lowStock: inventory.filter(item => item.quantity <= item.reorder).length,
    stockDifferences: inventory.filter(item => item.counted !== null && item.counted !== item.quantity).length,
    openingCash: branch.cash,
    expected,
    counted: branch.counted,
    difference: branch.counted === null ? null : branch.counted - expected,
  };
});
