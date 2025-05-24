//
//  ViewController.swift
//  FilamentTest
//
//  Created by Nikhil on 20/05/25.
//

import UIKit

class ViewController: UIViewController {
    private var filamentView: FilamentView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .red
        
        filamentView = FilamentView()
        view.addSubview(filamentView)
        
        filamentView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            filamentView.topAnchor.constraint(equalTo: view.topAnchor),
            filamentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            filamentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filamentView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        // Do any additional setup after loading the view.
    }
}
